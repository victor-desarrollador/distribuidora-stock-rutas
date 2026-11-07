#!/usr/bin/env python3
"""E-PL1 / H-02 — smoke tests HTTP contra un stack LOCAL de Supabase (GoTrue y PostgREST reales).

Lo lanza smoke_stack_local.sh con API_URL, ANON_KEY, SERVICE_ROLE_KEY y DB_CONTAINER. Crea
usuarios reales en GoTrue (API de administración), siembra los perfiles en la base local,
inicia sesión con contraseña para obtener JWT reales y llama a PostgREST con ellos.
NO reemplaza auth.uid(): usa el de GoTrue. Nunca escribe claves, contraseñas ni JWT en la
evidencia. Sólo stdlib. Código de salida distinto de cero si algún caso falla.
Uso: smoke_postgrest.py <archivo_resultados.tsv> <archivo_transcripcion.txt>
"""
import json, os, secrets, subprocess, sys, urllib.error, urllib.parse, urllib.request, uuid

API = os.environ["API_URL"].rstrip("/")
ANON, SRV, DB = os.environ["ANON_KEY"], os.environ["SERVICE_ROLE_KEY"], os.environ["DB_CONTAINER"]
RES, TRANS = sys.argv[1], sys.argv[2]
_u = urllib.parse.urlparse(API)
if _u.scheme != "http" or _u.hostname not in ("127.0.0.1", "localhost", "::1") or _u.username or _u.password:
    # Análisis exacto de la URL (no un prefijo): "http://localhost.otro.com" o
    # "http://127.0.0.1.otro.com" NO pasan. Las claves viajan en las cabeceras.
    sys.exit("abortado: el smoke sólo corre contra un stack local (http://127.0.0.1, localhost o ::1)")

res, trans, fallas = [], [], 0


def http(method, path, token=None, apikey=None, body=None, extra=None):
    h = {"apikey": apikey or ANON, "Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    h.update(extra or {})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def psql(sql):
    p = subprocess.run(["docker", "exec", "-i", DB, "psql", "-X", "-qtA", "-U", "postgres", "-d", "postgres",
                        "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if p.returncode:
        sys.exit("psql falló: " + p.stderr[:300])
    return p.stdout.strip()


def crear_usuario(nombre):
    email = f"smoke.{nombre}@usuarios.distribuidora.invalid"
    pw = secrets.token_urlsafe(18)
    st, tx = http("POST", "/auth/v1/admin/users", token=SRV, apikey=SRV,
                  body={"email": email, "password": pw, "email_confirm": True})
    if st not in (200, 201):
        sys.exit(f"no se pudo crear el usuario {nombre}: HTTP {st}")
    uid = json.loads(tx)["id"]
    st, tx = http("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": pw})
    if st != 200:
        sys.exit(f"no se pudo iniciar sesión {nombre}: HTTP {st}")
    return uid, json.loads(tx)["access_token"]


def chk(nombre, ok, detalle):
    global fallas
    if not ok:
        fallas += 1
    res.append(f"{'PASA' if ok else 'FALLA'}\t{nombre}\t{detalle}")


def llamar(nombre, method, path, token, esperado, apikey=None, body=None, extra=None, predicado=None):
    st, tx = http(method, path, token=token, apikey=apikey, body=body, extra=extra)
    trans.append(f"## {nombre}\n{method} {path}  (auth: {'JWT real' if token else 'sin JWT'}; apikey: {'anon' if (apikey in (None, ANON)) else 'otra'})\n"
                 f"-> HTTP {st}\n{tx[:1500]}\n")
    ok_st = st in esperado if isinstance(esperado, (set, tuple, list)) else st == esperado
    ok = ok_st
    det = f"HTTP {st}"
    if ok and predicado is not None:
        try:
            ok = bool(predicado(json.loads(tx)))
        except Exception as e:  # noqa: BLE001
            ok = False
            det += f" (predicado: {e})"
        if not ok:
            det += f" cuerpo={tx[:200]}"
    chk(nombre, ok, det)
    return st, tx


# --- Siembra: empresas A y B; usuarios reales de GoTrue; perfiles en la base ---
EA, EB = str(uuid.uuid4()), str(uuid.uuid4())
psql(f"insert into public.empresas (id, nombre) values ('{EA}', 'Smoke A'), ('{EB}', 'Smoke B');")
U = {}
for n in ("dueno_a", "encargado_a", "vendedor_a", "dueno_inactivo_a", "dueno_b", "vendedor_b", "sin_perfil"):
    U[n] = crear_usuario(n)
perfiles = [
    ("dueno_a", EA, "smoke.dueno.a", "Zeta Dueño", "dueno", True),
    ("encargado_a", EA, "smoke.enc.a", "alfa Encargado", "encargado", True),
    ("vendedor_a", EA, "smoke.vend.a", "  Beta Vendedor ", "vendedor_piloto", True),
    ("dueno_inactivo_a", EA, "smoke.inac.a", "Dueño inactivo A", "dueno", False),
    ("dueno_b", EB, "smoke.dueno.b", "Dueño B", "dueno", True),
    ("vendedor_b", EB, "smoke.vend.b", "Vendedor B", "vendedor_piloto", True),
]
for k, emp, usr, nom, rol, act in perfiles:
    psql("insert into public.perfiles (usuario_id, empresa_id, usuario, nombre, rol, activo) values "
         f"('{U[k][0]}', '{emp}', '{usr}', '{nom}', '{rol}', {'true' if act else 'false'});")

RPC = "/rest/v1/rpc/listar_vendedores_jornada"
NOMBRES_A = ["  Beta Vendedor ", "Zeta Dueño", "alfa Encargado"]  # orden COLLATE "C"
ids_a = {U["dueno_a"][0], U["encargado_a"][0], U["vendedor_a"][0]}

# --- Positivos ---
llamar("dueno_a POST rpc: 3 perfiles activos de A, orden C, columnas exactas", "POST", RPC, U["dueno_a"][1], 200, body={},
       predicado=lambda j: [r["nombre"] for r in j] == NOMBRES_A and all(set(r) == {"usuario_id", "nombre", "rol"} for r in j)
       and {r["usuario_id"] for r in j} == ids_a)
llamar("dueno_a GET rpc (función STABLE): mismo resultado", "GET", RPC, U["dueno_a"][1], 200,
       predicado=lambda j: [r["nombre"] for r in j] == NOMBRES_A)
llamar("encargado_a POST rpc: mismo resultado", "POST", RPC, U["encargado_a"][1], 200, body={},
       predicado=lambda j: [r["nombre"] for r in j] == NOMBRES_A)
llamar("dueno_b POST rpc: sólo los 2 de B", "POST", RPC, U["dueno_b"][1], 200, body={},
       predicado=lambda j: [r["nombre"] for r in j] == ["Dueño B", "Vendedor B"]
       and not ({r["usuario_id"] for r in j} & ids_a))

# --- Negativos de autorización/autenticación ---
def es_codigo(codigo, msg):
    return lambda j: j.get("code") == codigo and j.get("message") == msg

llamar("vendedor_a: PT403 jornada_no_autorizado", "POST", RPC, U["vendedor_a"][1], 403, body={}, predicado=es_codigo("PT403", "jornada_no_autorizado"))
llamar("vendedor_b: PT403", "POST", RPC, U["vendedor_b"][1], 403, body={}, predicado=es_codigo("PT403", "jornada_no_autorizado"))
llamar("dueno inactivo: PT403", "POST", RPC, U["dueno_inactivo_a"][1], 403, body={}, predicado=es_codigo("PT403", "jornada_no_autorizado"))
llamar("usuario sin perfil: PT403", "POST", RPC, U["sin_perfil"][1], 403, body={}, predicado=es_codigo("PT403", "jornada_no_autorizado"))
llamar("anon (apikey sin sesión): 401/403 por falta de EXECUTE", "POST", RPC, None, (401, 403), body={},
       predicado=lambda j: j.get("code") == "42501")
llamar("service_role (JWT de servicio): 403 por falta de EXECUTE (P11)", "POST", RPC, SRV, (401, 403), apikey=SRV, body={},
       predicado=lambda j: j.get("code") == "42501")

# --- privado no expuesto; perfiles sólo la fila propia ---
llamar("esquema privado no expuesto (rpc con Content-Profile: privado): 406", "POST", RPC, U["dueno_a"][1], 406, body={},
       extra={"Content-Profile": "privado"}, predicado=lambda j: j.get("code") == "PGRST106")
llamar("la vista protegida no se alcanza por la API (Accept-Profile: privado): 406", "GET", "/rest/v1/perfiles_empresa_gestion",
       U["dueno_a"][1], 406, extra={"Accept-Profile": "privado"}, predicado=lambda j: j.get("code") == "PGRST106")
llamar("dueno_a lee /perfiles: sólo su fila", "GET", "/rest/v1/perfiles?select=usuario_id,nombre", U["dueno_a"][1], 200,
       predicado=lambda j: len(j) == 1 and j[0]["usuario_id"] == U["dueno_a"][0])
llamar("encargado_a lee /perfiles: sólo su fila", "GET", "/rest/v1/perfiles?select=usuario_id", U["encargado_a"][1], 200,
       predicado=lambda j: len(j) == 1 and j[0]["usuario_id"] == U["encargado_a"][0])
llamar("dueno_a no lee el nombre de otros perfiles", "GET",
       f"/rest/v1/perfiles?select=nombre&usuario_id=neq.{U['dueno_a'][0]}", U["dueno_a"][1], 200, predicado=lambda j: j == [])
llamar("vendedor_a lee /perfiles: sólo su fila", "GET", "/rest/v1/perfiles?select=usuario_id", U["vendedor_a"][1], 200,
       predicado=lambda j: len(j) == 1 and j[0]["usuario_id"] == U["vendedor_a"][0])
llamar("anon no lee /perfiles", "GET", "/rest/v1/perfiles?select=usuario_id", None, (401, 403))

# --- Hechos del entorno (sin secretos) ---
uid_def = psql("select regexp_replace(prosrc, '\\s+', ' ', 'g') from pg_proc where oid = 'auth.uid'::regproc;")
chk("auth.uid() real del stack lee request.jwt.claims (definición de GoTrue, sin preludio)",
    "request.jwt.claims" in uid_def, uid_def)
hechos = [
    "version=" + psql("select version();"),
    "auth.uid=" + uid_def,
    "ultima_migracion_gotrue=" + psql("select max(version) from auth.schema_migrations;"),
    "politicas_perfiles=" + psql("select string_agg(policyname || ':' || cmd, ',' order by policyname) from pg_policies where tablename = 'perfiles';"),
]
with open(RES, "w") as f:
    f.write("\n".join(res) + f"\n--- casos: {len(res)}, fallas: {fallas}\n")
with open(TRANS, "w") as f:
    f.write("\n".join(hechos) + "\n\n" + "\n".join(trans))
print("\n".join(res)); print(f"--- casos: {len(res)}, fallas: {fallas}")
sys.exit(1 if fallas else 0)
