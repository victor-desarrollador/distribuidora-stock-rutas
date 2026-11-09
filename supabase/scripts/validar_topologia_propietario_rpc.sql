-- validar_topologia_propietario_rpc.sql
-- Preflight de topología: verifica invariantes de seguridad de roles,
-- esquemas, RPC y RLS según Topología D (ADR-001 P1/P2/P3/P4/P11, aprobado 24/10/2026).
-- Ésta es una consulta sola de solo lectura sobre los objetos persistentes.
-- Idempotente, determinista; devuelve error cuando falla una condición obligatoria.
--
-- Estructura:
--   0. Resolución de esquemas y roles por OID (fail-closed).
--   1. T3P-07: roles técnicos, membresías, herencia, ownership, esquemas y
--      privilegios efectivos de los roles técnicos y de la Data API.
--   2. T3P-05: RLS de todas las tablas expuestas (inventario obligatorio de 13
--      tablas + toda tabla adicional de public con RLS y sin FORCE).
--   3. Bloque A: funciones por firma exacta y OID (46 firmas, B.1.2a) e
--      inventario exhaustivo de funciones SECURITY DEFINER (3.7, ADR-001 §17.3),
--      con la excepción O-4 (ADR-001 §18.2 vigente) sujeta al contrato RB + RA
--      APROBADO SÓLO COMO NORMA (ADR-001 §18.2.1; O4-PGTEMP; ver la cabecera de DECLARE).
--   4. T3P-08: service_role y la excepción P11-productos (conjunto exacto).
--   5. T3P-06: manifiesto exacto de políticas RLS.
-- Cada rechazo indica el invariante violado entre corchetes.
-- Modo estricto (M-01): si faltan a la vez public.rls_auto_enable() y ensure_rls
-- se rechaza con [O4_AUSENTE]. Sólo en laboratorio local se acepta, de forma
-- explícita, creando en la MISMA sesión, antes de ejecutar este script:
--   CREATE TEMP TABLE preflight_o4_ausente_laboratorio (modo text);
--   INSERT INTO preflight_o4_ausente_laboratorio VALUES ('LABORATORIO_LOCAL_SIN_O4');
-- (única columna «modo», exactamente una fila con ese valor). El resultado es
-- [ESTADO_LOCAL_SIN_O4], nunca [ESTADO_A]. Con O-4 presente el marcador se rechaza.
-- No modifica la base: sólo lee el catálogo. El único cambio de estado es un
-- set_config(search_path, ..., is_local = true) dentro de la propia
-- transacción, restaurado al terminar la sección 5.

DO $$
DECLARE
  -- OIDs de esquema (calificados con pg_catalog para evitar resolución en pg_temp)
  v_oid_publico pg_catalog.oid;
  v_oid_privado pg_catalog.oid;

  -- OIDs de roles
  v_oid_propietario_rpc pg_catalog.oid;
  v_oid_lector_perfiles_rpc pg_catalog.oid;
  v_oid_service_role pg_catalog.oid;
  v_oid_postgres pg_catalog.oid;

  -- Variables auxiliares
  v_count integer;
  v_pol_count integer;

  -- Bloque A (T3P-01/T3P-03/T3P-04): verificación por firma exacta y OID
  v_m record;                -- fila del manifiesto
  v_oid_fn pg_catalog.oid;   -- OID resuelto desde la firma exacta
  v_owner_fn pg_catalog.oid;
  v_lang_fn pg_catalog.text;
  v_kind_fn pg_catalog.text;
  v_secdef_fn pg_catalog.bool;
  v_vol_fn pg_catalog.text;
  v_config_fn pg_catalog.text[];
  v_acl_fn pg_catalog.text;
  v_distrib pg_catalog.text;
  v_violaciones pg_catalog.text;  -- BA2-01: acumulador de violaciones
  v_sd_manifiesto pg_catalog.oid[] := ARRAY[]::pg_catalog.oid[];  -- B.1.2a: OID SD del manifiesto
  v_sd_aprobadas pg_catalog.oid[];                                -- B.1.2a: inventario SD aprobado
  v_oid_graphql_public pg_catalog.oid;                            -- B.1.2a: puede ser NULL
  -- Referencias de O-4. Tres niveles distintos:
  --   1. VIGENTE — ADR-001 §18.2 (aprobada para validación controlada): se
  --      conservan public.rls_auto_enable() y ensure_rls, sin EXECUTE para
  --      PUBLIC/anon/authenticated/service_role, sin modificar el
  --      comportamiento funcional. §18.2 NO fija hash ni proconfig.
  --   2. HISTÓRICO — B.1.2b/B.1.2c (ratificación humana del 06/11/2026, sólo
  --      para este preflight): hash 325ae266… y proconfig {search_path=pg_catalog}
  --      del cuerpo observado en staging. O4-PGTEMP demostró que ese cuerpo es
  --      vulnerable; ya no es la referencia y el preflight lo rechaza.
  --   3. APROBADO SÓLO COMO NORMA — contrato RB + RA (ADR-001 §18.2.1,
  --      07/11/2026; migración local 20261110120000, no autorizada en staging
  --      ni producción): el mismo cuerpo con
  --      cmd pg_catalog.record, tbl pg_catalog.name y
  --      FROM pg_catalog.pg_event_trigger_ddl_commands(), y proconfig
  --      {search_path=pg_catalog, pg_temp}. Los valores de abajo son los de
  --      este nivel 3. Identidad, no certificación.
  -- Expresión del hash: encode(sha256(convert_to(prosrc, 'UTF8')), 'hex').
  v_o4_lenguaje CONSTANT pg_catalog.text := 'plpgsql';
  v_o4_sha256_prosrc CONSTANT pg_catalog.text := 'e1b231fb7db1d25c9dfab71d09dbc968c092c00c0049aca1f529f7e79296fb6e';
  v_o4_proconfig CONSTANT pg_catalog.text[] := ARRAY['search_path=pg_catalog, pg_temp']::pg_catalog.text[];
  v_o4_funcion pg_catalog.text;      -- violaciones de la función
  v_o4_triggers pg_catalog.text;     -- violaciones de los event triggers
  v_o4_n_ensure pg_catalog.int8;     -- ensure_rls asociados a la función (debe ser 1)
  v_o4_trg_tabla pg_catalog.bool;    -- algún trigger de tabla usa la función
  -- M-01: modo estricto por defecto. O-4 ausente sólo se acepta con el
  -- marcador explícito de laboratorio local (tabla temporal de sesión).
  v_marc_nombre CONSTANT pg_catalog.text := 'preflight_o4_ausente_laboratorio';
  v_marc_valor CONSTANT pg_catalog.text := 'LABORATORIO_LOCAL_SIN_O4';
  v_marc_oid pg_catalog.oid;
  v_marc_nsp pg_catalog.text;
  v_marc_err pg_catalog.text;
  v_marc_filas pg_catalog.int8;
  v_marc_ok pg_catalog.int8;
  v_modo_local pg_catalog.bool := false;  -- true sólo con marcador válido y O-4 ausente

  -- Bloque B (T3P-05..T3P-08)
  v_b record;                                   -- fila de manifiesto o de catálogo
  v_txt pg_catalog.text;                        -- valor real agregado
  v_txt2 pg_catalog.text;                       -- segundo agregado (B11-02/B11-03)
  v_oid_rol pg_catalog.oid;
  v_oid_rel pg_catalog.oid;
  v_oid_authenticated pg_catalog.oid;
  v_oid_anon pg_catalog.oid;
  v_oid_authenticator pg_catalog.oid;
  v_search_path_previo pg_catalog.text;
  v_politicas pg_catalog.text[];
  v_rels_manifiesto pg_catalog.oid[];          -- B11-02: relaciones del manifiesto de políticas
  v_pendientes integer := 0;                   -- B11-04: superficies sin contrato auditado
  v_pol_cmd pg_catalog.text;
  v_pol_perm pg_catalog.bool;
  v_pol_roles pg_catalog.text;
  v_pol_using pg_catalog.text;
  v_pol_check pg_catalog.text;
BEGIN
  -- ======================================================
  -- 0. Resolución de esquemas y roles por OID (fail-closed)
  -- ======================================================
  v_oid_publico := pg_catalog.to_regnamespace('public');
  v_oid_privado := pg_catalog.to_regnamespace('privado');
  IF v_oid_publico IS NULL OR v_oid_privado IS NULL THEN
    RAISE EXCEPTION 'validar_topologia: [ESQUEMA_AUSENTE] falta el esquema public o privado.';
  END IF;

  v_oid_propietario_rpc := pg_catalog.to_regrole('propietario_rpc');
  v_oid_lector_perfiles_rpc := pg_catalog.to_regrole('lector_perfiles_rpc');
  v_oid_service_role := pg_catalog.to_regrole('service_role');
  v_oid_postgres := pg_catalog.to_regrole('postgres');
  v_oid_authenticated := pg_catalog.to_regrole('authenticated');
  v_oid_anon := pg_catalog.to_regrole('anon');
  v_oid_authenticator := pg_catalog.to_regrole('authenticator');
  IF v_oid_propietario_rpc IS NULL OR v_oid_lector_perfiles_rpc IS NULL
     OR v_oid_service_role IS NULL OR v_oid_postgres IS NULL
     OR v_oid_authenticated IS NULL OR v_oid_anon IS NULL OR v_oid_authenticator IS NULL THEN
    RAISE EXCEPTION 'validar_topologia: [ROL_AUSENTE] falta alguno de los roles propietario_rpc, lector_perfiles_rpc, service_role, postgres, authenticated, anon o authenticator.';
  END IF;

  -- ======================================================
  -- 1. T3P-07: roles técnicos, membresías, ownership y privilegios efectivos
  -- ======================================================
  -- Contrato: ADR-001 §7 (P3/P4), §18.2 (O-3), §18.4.2 y §18.4.2.1 (D-2);
  -- migraciones 20261024232059, 20261029233000 y 20261105130000 (B1);
  -- tests hardening_adr001.test.sql (O-3, D-2/P1), lector_perfiles_rpc.test.sql
  -- y grants_default_privileges.test.sql.

  -- 1.1 Atributos: NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS.
  FOR v_b IN
    SELECT r.rolname::pg_catalog.text AS rol, r.rolsuper, r.rolcanlogin, r.rolcreatedb,
           r.rolcreaterole, r.rolreplication, r.rolbypassrls
      FROM pg_catalog.pg_roles r
     WHERE r.oid IN (v_oid_propietario_rpc, v_oid_lector_perfiles_rpc)
  LOOP
    IF v_b.rolsuper OR v_b.rolcanlogin OR v_b.rolcreatedb OR v_b.rolcreaterole
       OR v_b.rolreplication OR v_b.rolbypassrls THEN
      RAISE EXCEPTION 'validar_topologia: [ROL_ATRIBUTOS] % tiene atributos fuera de NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS.', v_b.rol;
    END IF;
  END LOOP;

  -- 1.2 Membresías entrantes exactas (formato de B1): sólo postgres, con la
  --     fila O-3 (SET sin INHERIT ni ADMIN, otorgada por postgres) y la fila
  --     automática de CREATE ROLE (ADMIN sin SET ni INHERIT, otorgada por un
  --     superusuario). Se comparan TODAS las filas, no la existencia de una.
  FOR v_b IN
    SELECT x.rol, pg_catalog.to_regrole(x.rol) AS oid_rol
      FROM (VALUES ('propietario_rpc'), ('lector_perfiles_rpc')) AS x(rol)
  LOOP
    SELECT pg_catalog.string_agg(y.fila, ',' ORDER BY y.fila) INTO v_txt
      FROM (SELECT m.member::pg_catalog.regrole::pg_catalog.text
                   || '|' || m.admin_option::pg_catalog.text
                   || '|' || m.inherit_option::pg_catalog.text
                   || '|' || m.set_option::pg_catalog.text
                   || '|' || CASE WHEN m.grantor = v_oid_postgres THEN 'postgres'
                                  WHEN g.rolsuper THEN 'superusuario'
                                  ELSE 'otro' END AS fila
              FROM pg_catalog.pg_auth_members m
              JOIN pg_catalog.pg_roles g ON g.oid = m.grantor
             WHERE m.roleid = v_b.oid_rol) AS y;

    IF v_txt IS DISTINCT FROM 'postgres|false|false|true|postgres,postgres|true|false|false|superusuario' THEN
      RAISE EXCEPTION 'validar_topologia: [MEMBRESIA_ENTRANTE] membresías de % fuera del contrato (miembro|admin|inherit|set|grantor): %. Esperado: postgres|false|false|true|postgres,postgres|true|false|false|superusuario.',
        v_b.rol, COALESCE(v_txt, 'ninguna');
    END IF;
  END LOOP;

  -- 1.3 Membresías salientes: los roles técnicos no son miembros de ningún rol.
  SELECT pg_catalog.string_agg(m.member::pg_catalog.regrole::pg_catalog.text || ' -> '
                               || m.roleid::pg_catalog.regrole::pg_catalog.text, ', ' ORDER BY 1)
    INTO v_txt
    FROM pg_catalog.pg_auth_members m
   WHERE m.member IN (v_oid_propietario_rpc, v_oid_lector_perfiles_rpc);
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [MEMBRESIA_SALIENTE] un rol técnico es miembro de otro rol: %.', v_txt;
  END IF;

  -- 1.4 Efectivo (O-3 / D-2): postgres puede SET ROLE pero no hereda; los roles
  --     de la Data API y el otro rol técnico no pueden SET, heredar ni ser
  --     miembros, ni directa ni indirectamente (pg_has_role recorre la cadena).
  FOR v_b IN
    SELECT x.rol FROM (VALUES ('propietario_rpc'), ('lector_perfiles_rpc')) AS x(rol)
  LOOP
    IF NOT pg_catalog.pg_has_role('postgres', v_b.rol, 'SET')
       OR pg_catalog.pg_has_role('postgres', v_b.rol, 'USAGE') THEN
      RAISE EXCEPTION 'validar_topologia: [O3_SET_INHERIT] postgres debe poder SET ROLE % sin heredar sus privilegios (SET=%, USAGE=%).',
        v_b.rol, pg_catalog.pg_has_role('postgres', v_b.rol, 'SET'),
        pg_catalog.pg_has_role('postgres', v_b.rol, 'USAGE');
    END IF;
  END LOOP;

  SELECT pg_catalog.string_agg(x.quien || ' -> ' || x.rol, ', ' ORDER BY x.quien, x.rol) INTO v_txt
    FROM (SELECT q.quien, t.rol
            FROM (VALUES ('anon'), ('authenticated'), ('authenticator'), ('service_role'),
                         ('propietario_rpc'), ('lector_perfiles_rpc')) AS q(quien),
                 (VALUES ('propietario_rpc'), ('lector_perfiles_rpc')) AS t(rol)
           WHERE q.quien <> t.rol
             AND (pg_catalog.pg_has_role(q.quien, t.rol, 'MEMBER')
                  OR pg_catalog.pg_has_role(q.quien, t.rol, 'SET')
                  OR pg_catalog.pg_has_role(q.quien, t.rol, 'USAGE'))) AS x;
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [MEMBRESIA_EFECTIVA] membresía, SET o herencia efectiva no autorizada: %.', v_txt;
  END IF;

  -- 1.5 Esquemas: privado de postgres; sin CREATE efectivo para roles técnicos
  --     ni Data API en public/privado; sin USAGE sobre privado para
  --     lector_perfiles_rpc y anon; lector_perfiles_rpc sin grants de esquema
  --     propios (C-1). service_role se controla en la sección 4.
  IF (SELECT n.nspowner FROM pg_catalog.pg_namespace n WHERE n.oid = v_oid_privado)
     IS DISTINCT FROM v_oid_postgres THEN
    RAISE EXCEPTION 'validar_topologia: [ESQUEMA_OWNER] el esquema privado no es de postgres.';
  END IF;

  SELECT pg_catalog.string_agg(q.rol || ' CREATE ' || s.esq, ', ' ORDER BY q.rol, s.esq) INTO v_txt
    FROM (VALUES ('propietario_rpc'), ('lector_perfiles_rpc'), ('anon'), ('authenticated')) AS q(rol),
         (VALUES ('public'), ('privado')) AS s(esq)
   WHERE pg_catalog.has_schema_privilege(q.rol, s.esq, 'CREATE');
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [CREATE_ESQUEMA] CREATE efectivo no autorizado: %.', v_txt;
  END IF;

  IF pg_catalog.has_schema_privilege('lector_perfiles_rpc', 'privado', 'USAGE')
     OR pg_catalog.has_schema_privilege('anon', 'privado', 'USAGE') THEN
    RAISE EXCEPTION 'validar_topologia: [USAGE_ESQUEMA] lector_perfiles_rpc o anon tienen USAGE sobre privado.';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n,
                    LATERAL pg_catalog.aclexplode(n.nspacl) a
              WHERE a.grantee = v_oid_lector_perfiles_rpc) THEN
    RAISE EXCEPTION 'validar_topologia: [ACL_ESQUEMA] lector_perfiles_rpc figura en la ACL de algún esquema.';
  END IF;

  -- 1.6 Ownership.
  --     propietario_rpc: ninguna relación ni esquema; funciones sólo en privado;
  --     toda función de privado es suya (P3, hardening O-3).
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.relowner = v_oid_propietario_rpc)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspowner = v_oid_propietario_rpc)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.proowner = v_oid_propietario_rpc AND p.pronamespace <> v_oid_privado)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.pronamespace = v_oid_privado AND p.proowner <> v_oid_propietario_rpc) THEN
    RAISE EXCEPTION 'validar_topologia: [OWNERSHIP_PROPIETARIO_RPC] propietario_rpc es dueño de relaciones, esquemas o funciones fuera de privado, o hay funciones de privado de otro owner.';
  END IF;

  --     lector_perfiles_rpc: sólo la vista privado.perfiles_empresa_gestion.
  v_oid_rel := pg_catalog.to_regclass('privado.perfiles_empresa_gestion');
  IF v_oid_rel IS NULL THEN
    RAISE EXCEPTION 'validar_topologia: [VISTA_PRIVADA] falta privado.perfiles_empresa_gestion.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
              WHERE c.relowner = v_oid_lector_perfiles_rpc AND c.oid <> v_oid_rel)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proowner = v_oid_lector_perfiles_rpc)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspowner = v_oid_lector_perfiles_rpc) THEN
    RAISE EXCEPTION 'validar_topologia: [OWNERSHIP_LECTOR] lector_perfiles_rpc es dueño de algo más que privado.perfiles_empresa_gestion.';
  END IF;

  --     Vista privada: owner, tipo, reloptions y ACL exactos (§18.4.2.1).
  SELECT c.relkind::pg_catalog.text || '|' || c.relowner::pg_catalog.regrole::pg_catalog.text
         || '|' || COALESCE(pg_catalog.array_to_string(
                     ARRAY(SELECT o FROM pg_catalog.unnest(c.reloptions) o ORDER BY 1), ','), '-')
         || '|' || COALESCE(pg_catalog.array_to_string(
                     ARRAY(SELECT a::pg_catalog.text FROM pg_catalog.unnest(c.relacl) a ORDER BY 1), ','), '-')
    INTO v_txt
    FROM pg_catalog.pg_class c WHERE c.oid = v_oid_rel;
  IF v_txt IS DISTINCT FROM
     'v|lector_perfiles_rpc|security_barrier=true,security_invoker=false|lector_perfiles_rpc=arwdDxtm/lector_perfiles_rpc,propietario_rpc=r/lector_perfiles_rpc' THEN
    RAISE EXCEPTION 'validar_topologia: [VISTA_PRIVADA] privado.perfiles_empresa_gestion fuera de contrato (tipo|owner|reloptions|ACL): %.', v_txt;
  END IF;

  --     Roles de la Data API: no son dueños de nada en public ni privado.
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
              WHERE c.relnamespace IN (v_oid_publico, v_oid_privado)
                AND c.relowner IN (v_oid_anon, v_oid_authenticated, v_oid_authenticator, v_oid_service_role))
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.pronamespace IN (v_oid_publico, v_oid_privado)
                   AND p.proowner IN (v_oid_anon, v_oid_authenticated, v_oid_authenticator, v_oid_service_role))
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
                 WHERE n.oid IN (v_oid_publico, v_oid_privado)
                   AND n.nspowner IN (v_oid_anon, v_oid_authenticated, v_oid_authenticator, v_oid_service_role)) THEN
    RAISE EXCEPTION 'validar_topologia: [OWNERSHIP_DATA_API] un rol de la Data API es dueño de objetos de public o privado.';
  END IF;

  -- 1.7 Privilegios efectivos de tabla y columna (incluye PUBLIC y membresías).
  --     anon: ninguno; authenticated: sólo SELECT (grants_default_privileges);
  --     sin privilegios por columna de escritura. stock_actual: anon sin
  --     SELECT; authenticated sin INSERT/UPDATE/DELETE (20261025021032).
  SELECT pg_catalog.string_agg(q.rol || ' ' || p.priv || ' ' || t.tabla, ', ' ORDER BY q.rol, t.tabla, p.priv)
    INTO v_txt
    FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                 ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                 ('public.operaciones'), ('public.movimientos_stock'),
                 ('public.jornadas'), ('public.reasignaciones_vendedor'),
                 ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) AS t(tabla),
         (VALUES ('anon'), ('authenticated')) AS q(rol),
         (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                 ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) AS p(priv)
   WHERE pg_catalog.to_regclass(t.tabla) IS NOT NULL
     AND pg_catalog.has_table_privilege(q.rol, pg_catalog.to_regclass(t.tabla), p.priv)
         IS DISTINCT FROM (q.rol = 'authenticated' AND p.priv = 'SELECT'
                AND t.tabla NOT IN ('public.intenciones_operacion', 'public.intenciones_reconocimientos'));
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [ACCESO_DATA_API] privilegio de tabla efectivo fuera de contrato (rol privilegio tabla, distinto de lo esperado): %.', v_txt;
  END IF;

  SELECT pg_catalog.string_agg(q.rol || ' ' || t.tabla, ', ' ORDER BY q.rol, t.tabla) INTO v_txt
    FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                 ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                 ('public.operaciones'), ('public.movimientos_stock'),
                 ('public.jornadas'), ('public.reasignaciones_vendedor'),
                 ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) AS t(tabla),
         (VALUES ('anon'), ('authenticated')) AS q(rol)
   WHERE pg_catalog.to_regclass(t.tabla) IS NOT NULL
     AND (pg_catalog.has_any_column_privilege(q.rol, pg_catalog.to_regclass(t.tabla), 'INSERT, UPDATE, REFERENCES')
          OR (q.rol = 'anon'
              AND pg_catalog.has_any_column_privilege(q.rol, pg_catalog.to_regclass(t.tabla), 'SELECT'))
          OR (t.tabla IN ('public.intenciones_operacion', 'public.intenciones_reconocimientos')
              AND pg_catalog.has_any_column_privilege(q.rol, pg_catalog.to_regclass(t.tabla), 'SELECT')));
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [ACCESO_DATA_API_COLUMNA] privilegio por columna no autorizado: %.', v_txt;
  END IF;

  v_oid_rel := pg_catalog.to_regclass('public.stock_actual');
  IF v_oid_rel IS NOT NULL
     AND (pg_catalog.has_table_privilege('anon', v_oid_rel, 'SELECT')
          OR pg_catalog.has_table_privilege('authenticated', v_oid_rel, 'INSERT, UPDATE, DELETE')) THEN
    RAISE EXCEPTION 'validar_topologia: [ACCESO_DATA_API] stock_actual: anon con SELECT o authenticated con escritura.';
  END IF;

  --     lector_perfiles_rpc: sólo SELECT (usuario_id, empresa_id, rol, activo)
  --     sobre public.perfiles; nada más en las tablas de negocio.
  v_oid_rel := pg_catalog.to_regclass('public.perfiles');
  SELECT pg_catalog.string_agg(a.attname::pg_catalog.text, ',' ORDER BY a.attname) INTO v_txt
    FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = v_oid_rel AND a.attnum > 0 AND NOT a.attisdropped
     AND pg_catalog.has_column_privilege('lector_perfiles_rpc', v_oid_rel, a.attnum, 'SELECT');
  IF v_txt IS DISTINCT FROM 'activo,empresa_id,rol,usuario_id' THEN
    RAISE EXCEPTION 'validar_topologia: [PRIV_LECTOR] columnas de perfiles legibles por lector_perfiles_rpc: %, se esperaba activo,empresa_id,rol,usuario_id.',
      COALESCE(v_txt, 'ninguna');
  END IF;

  SELECT pg_catalog.string_agg(t.tabla, ', ' ORDER BY t.tabla) INTO v_txt
    FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                 ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                 ('public.operaciones'), ('public.movimientos_stock'),
                 ('public.jornadas'), ('public.reasignaciones_vendedor'),
                 ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos'), ('public.stock_actual')) AS t(tabla)
   WHERE pg_catalog.to_regclass(t.tabla) IS NOT NULL
     AND (pg_catalog.has_table_privilege('lector_perfiles_rpc', pg_catalog.to_regclass(t.tabla),
            'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
          OR pg_catalog.has_any_column_privilege('lector_perfiles_rpc', pg_catalog.to_regclass(t.tabla),
            'INSERT, UPDATE, REFERENCES')
          OR (t.tabla <> 'public.perfiles'
              AND pg_catalog.has_any_column_privilege('lector_perfiles_rpc', pg_catalog.to_regclass(t.tabla), 'SELECT')));
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [PRIV_LECTOR] lector_perfiles_rpc tiene privilegios no autorizados sobre: %.', v_txt;
  END IF;

  --     propietario_rpc: sin UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN
  --     ni UPDATE/REFERENCES por columna sobre operaciones y movimientos_stock
  --     (20261025021032, ADR §18.4); sin escritura sobre perfiles; sin DELETE
  --     sobre jornadas (ADR §18.4.2).
  IF pg_catalog.has_table_privilege('propietario_rpc', pg_catalog.to_regclass('public.operaciones'),
       'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('propietario_rpc', pg_catalog.to_regclass('public.operaciones'), 'UPDATE, REFERENCES')
     OR pg_catalog.has_table_privilege('propietario_rpc', pg_catalog.to_regclass('public.movimientos_stock'),
       'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
     OR pg_catalog.has_any_column_privilege('propietario_rpc', pg_catalog.to_regclass('public.movimientos_stock'), 'UPDATE, REFERENCES')
     OR pg_catalog.has_table_privilege('propietario_rpc', pg_catalog.to_regclass('public.perfiles'), 'INSERT, UPDATE, DELETE, TRUNCATE')
     OR pg_catalog.has_any_column_privilege('propietario_rpc', pg_catalog.to_regclass('public.perfiles'), 'INSERT, UPDATE')
     OR pg_catalog.has_table_privilege('propietario_rpc', pg_catalog.to_regclass('public.jornadas'), 'DELETE') THEN
    RAISE EXCEPTION 'validar_topologia: [PRIV_PROPIETARIO_RPC] propietario_rpc tiene un privilegio prohibido sobre operaciones, movimientos_stock, perfiles o jornadas.';
  END IF;

  RAISE NOTICE 'validar_topologia: [T3P-07] roles, membresías, ownership y privilegios efectivos conformes.';

  -- ======================================================
  -- 2. T3P-05: RLS de todas las tablas expuestas
  -- ======================================================
  -- Contrato: ADR-001 §7 P4 (toda tabla expuesta con RLS obligatoria, sin
  -- FORCE, owner de migraciones); inventario de tablas de negocio de
  -- hardening_adr001.test.sql y grants_default_privileges.test.sql; vista
  -- stock_actual security_invoker (20261025021032, stock_ingreso.test.sql).
  -- No se filtra por relrowsecurity: se parte del inventario y de pg_class.
  FOR v_b IN
    SELECT t.tabla
      FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                   ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                   ('public.operaciones'), ('public.movimientos_stock'),
                   ('public.jornadas'), ('public.reasignaciones_vendedor'),
                   ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) AS t(tabla)
  LOOP
    v_oid_rel := pg_catalog.to_regclass(v_b.tabla);
    IF v_oid_rel IS NULL THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_TABLA_AUSENTE] falta la tabla %.', v_b.tabla;
    END IF;

    SELECT c.relkind::pg_catalog.text || '|' || c.relowner::pg_catalog.regrole::pg_catalog.text
           || '|' || c.relrowsecurity::pg_catalog.text || '|' || c.relforcerowsecurity::pg_catalog.text
      INTO v_txt
      FROM pg_catalog.pg_class c WHERE c.oid = v_oid_rel;

    IF pg_catalog.split_part(v_txt, '|', 1) IS DISTINCT FROM 'r' THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_TIPO] % (oid %) no es una tabla ordinaria: %.', v_b.tabla, v_oid_rel, v_txt;
    END IF;
    IF pg_catalog.split_part(v_txt, '|', 2) IS DISTINCT FROM 'postgres' THEN
      RAISE EXCEPTION 'validar_topologia: [OWNERSHIP_TABLA] % (oid %) tiene owner %, se esperaba postgres (P4).',
        v_b.tabla, v_oid_rel, pg_catalog.split_part(v_txt, '|', 2);
    END IF;
    IF pg_catalog.split_part(v_txt, '|', 3) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_DESHABILITADA] % (oid %) tiene RLS deshabilitada (P4).', v_b.tabla, v_oid_rel;
    END IF;
    IF pg_catalog.split_part(v_txt, '|', 4) IS DISTINCT FROM 'false' THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_FORCE] % (oid %) tiene FORCE ROW LEVEL SECURITY, prohibido sin decisión específica (P4).', v_b.tabla, v_oid_rel;
    END IF;
  END LOOP;

  --     Vista expuesta aprobada: public.stock_actual, owner postgres, security_invoker.
  v_oid_rel := pg_catalog.to_regclass('public.stock_actual');
  IF v_oid_rel IS NULL
     OR (SELECT c.relkind::pg_catalog.text || '|' || c.relowner::pg_catalog.regrole::pg_catalog.text
                || '|' || (COALESCE(c.reloptions, ARRAY[]::pg_catalog.text[])
                           @> ARRAY['security_invoker=true']::pg_catalog.text[])::pg_catalog.text
           FROM pg_catalog.pg_class c WHERE c.oid = v_oid_rel)
        IS DISTINCT FROM 'v|postgres|true' THEN
    RAISE EXCEPTION 'validar_topologia: [VISTA_EXPUESTA] public.stock_actual falta o no es una vista de postgres con security_invoker=true.';
  END IF;

  --     Tablas expuestas adicionales (T3P-05, B.1.1): P4 exige RLS en toda tabla
  --     expuesta y prohíbe FORCE sin decisión específica para esa tabla (no hay
  --     ninguna aprobada). Una tabla ordinaria ('r', incluidas particiones) o
  --     particionada ('p') de public fuera del inventario no se rechaza por no
  --     estar inventariada: sólo por RLS deshabilitada o por FORCE. Las 13
  --     tablas y stock_actual se excluyen por OID (ya validadas arriba).
  --     B11-01 (decisión humana): no se impone owner postgres a tablas futuras.
  --     El owner exacto se exige sólo a las 13 tablas (arriba); las prohibiciones
  --     aprobadas de owner (roles técnicos y Data API, sección 1.6) siguen. El
  --     owner de cada tabla adicional se informa como PENDIENTE DE DECISIÓN y no
  --     se declara validado.
  FOR v_b IN
    SELECT c.oid, c.relname::pg_catalog.text AS relname, c.relkind::pg_catalog.text AS relkind,
           c.relrowsecurity, c.relforcerowsecurity, c.relowner
      FROM pg_catalog.pg_class c
     WHERE c.relnamespace = v_oid_publico
       AND c.relkind IN ('r', 'p')
       AND c.oid <> ALL (ARRAY(
             SELECT pg_catalog.to_regclass(t.rel)::pg_catalog.oid
               FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                            ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                            ('public.operaciones'), ('public.movimientos_stock'),
                            ('public.jornadas'), ('public.reasignaciones_vendedor'),
                            ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos'), ('public.stock_actual')) AS t(rel)))
     ORDER BY c.relname, c.oid
  LOOP
    IF v_b.relrowsecurity IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_DESHABILITADA] tabla adicional public.% (oid %, relkind %) tiene RLS deshabilitada (P4: toda tabla expuesta con RLS obligatoria).',
        v_b.relname, v_b.oid, v_b.relkind;
    END IF;
    IF v_b.relforcerowsecurity IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'validar_topologia: [RLS_FORCE] tabla adicional public.% (oid %, relkind %) tiene FORCE ROW LEVEL SECURITY, prohibido sin decisión específica (P4).',
        v_b.relname, v_b.oid, v_b.relkind;
    END IF;
    RAISE WARNING 'validar_topologia: [PENDIENTE_DECISION_OWNER] tabla adicional public.% (oid %, relkind %) con RLS y sin FORCE; owner % NO VALIDADO (owner de migraciones para tablas futuras pendiente de decisión).',
      v_b.relname, v_b.oid, v_b.relkind, COALESCE(v_b.relowner::pg_catalog.regrole::pg_catalog.text, 'desconocido');
    v_pendientes := v_pendientes + 1;
  END LOOP;

  --     B11-03: vistas ('v') adicionales de public que eluden RLS (Blueprint
  --     §7.3 y §10: aislamiento por empresa_id mediante RLS en las tablas
  --     expuestas, sin confiar en otro control). Método:
  --       1. Raíz: vista o vista materializada adicional de public con algún
  --          privilegio efectivo (tabla o columna; incluye PUBLIC y membresías)
  --          para anon o authenticated.
  --       2. Recorrido transitivo de las relaciones que lee cada regla de
  --          pg_rewrite (pg_depend, refclassid pg_class: FROM, JOIN,
  --          subconsultas, CTE, LATERAL, UNION y constantes regclass), a través
  --          de vistas y vistas materializadas, sin ciclos y con profundidad 32.
  --       3. Rol que lee las relaciones de cada nodo (no se hereda; regla de
  --          PostgreSQL, CREATE VIEW): vista sin security_invoker -> su owner;
  --          vista con security_invoker=true -> siempre el llamador, aunque se
  --          acceda desde una vista sin security_invoker; vista materializada
  --          -> su owner (sus datos se calculan como su owner).
  --       4. Elusión: una tabla con RLS leída por un owner que la saltea
  --          (superusuario, BYPASSRLS, o miembro con herencia de su owner sin
  --          FORCE).
  --     Las funciones invocadas por la vista se ejecutan como el llamador (o
  --     como su owner si son SECURITY DEFINER) y su EXECUTE se verifica contra
  --     el llamador: no agregan acceso por la vista (evidencia de B.1.1c).
  --     Una vista raíz con elusión se rechaza; una vista materializada raíz con
  --     elusión se informa (sin regla general aprobada).
  SELECT pg_catalog.string_agg(DISTINCT x.descr, '; ') FILTER (WHERE x.raiz_kind = 'v'),
         pg_catalog.string_agg(DISTINCT x.descr, '; ') FILTER (WHERE x.raiz_kind = 'm')
    INTO v_txt, v_txt2
    FROM (
      WITH RECURSIVE
      raiz AS (
        SELECT c.oid, c.relkind::pg_catalog.text AS relkind, c.relowner, c.reloptions, a.acceso
          FROM pg_catalog.pg_class c
          CROSS JOIN LATERAL (
            SELECT pg_catalog.string_agg(q.rol, '+' ORDER BY q.rol) AS acceso
              FROM (VALUES ('anon'), ('authenticated')) AS q(rol)
             WHERE pg_catalog.has_table_privilege(q.rol, c.oid,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                OR pg_catalog.has_any_column_privilege(q.rol, c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')) AS a
         WHERE c.relnamespace = v_oid_publico
           AND c.relkind IN ('v', 'm')
           AND c.oid IS DISTINCT FROM pg_catalog.to_regclass('public.stock_actual')::pg_catalog.oid
           AND a.acceso IS NOT NULL),
      camino (raiz, raiz_kind, acceso, nodo, lector, lector_hijos, prof, ruta) AS (
        SELECT r.oid, r.relkind, r.acceso, r.oid, NULL::pg_catalog.oid,
               CASE WHEN r.relkind = 'm'
                         OR NOT COALESCE((SELECT o.option_value::pg_catalog.bool
                                            FROM pg_catalog.pg_options_to_table(r.reloptions) AS o
                                           WHERE o.option_name = 'security_invoker'), false)
                    THEN r.relowner END,
               0, ARRAY[r.oid]
          FROM raiz r
        UNION ALL
        SELECT k.raiz, k.raiz_kind, k.acceso, h.oid, k.lector_hijos,
               CASE WHEN h.relkind = 'm'
                         OR (h.relkind = 'v'
                             AND NOT COALESCE((SELECT o.option_value::pg_catalog.bool
                                                 FROM pg_catalog.pg_options_to_table(h.reloptions) AS o
                                                WHERE o.option_name = 'security_invoker'), false))
                    THEN h.relowner END,
               k.prof + 1, k.ruta || h.oid
          FROM camino k
          JOIN pg_catalog.pg_class n ON n.oid = k.nodo AND n.relkind IN ('v', 'm')
          CROSS JOIN LATERAL (
            SELECT DISTINCT dd.refobjid
              FROM pg_catalog.pg_rewrite w
              JOIN pg_catalog.pg_depend dd
                ON dd.classid = 'pg_catalog.pg_rewrite'::pg_catalog.regclass
               AND dd.objid = w.oid
               AND dd.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass
             WHERE w.ev_class = k.nodo AND dd.refobjid <> k.nodo) AS d
          JOIN pg_catalog.pg_class h ON h.oid = d.refobjid
         WHERE h.oid <> ALL (k.ruta) AND k.prof < 32)
      SELECT k.raiz_kind,
             CASE WHEN t.relkind IN ('v', 'm') AND k.prof >= 32
                  THEN 'public.' || pg_catalog.quote_ident(rc.relname::pg_catalog.text)
                       || ' (oid ' || k.raiz::pg_catalog.text || ', accesible por ' || k.acceso
                       || '): profundidad de dependencias mayor que 32, no clasificable'
                  ELSE 'public.' || pg_catalog.quote_ident(rc.relname::pg_catalog.text)
                       || ' (oid ' || k.raiz::pg_catalog.text || ', relkind ' || k.raiz_kind
                       || ', accesible por ' || k.acceso || ') lee '
                       || t.oid::pg_catalog.regclass::pg_catalog.text || ' (RLS) como '
                       || COALESCE(k.lector::pg_catalog.regrole::pg_catalog.text, 'desconocido')
                       || ', que saltea su RLS' END AS descr
        FROM camino k
        JOIN pg_catalog.pg_class t ON t.oid = k.nodo
        JOIN pg_catalog.pg_class rc ON rc.oid = k.raiz
       WHERE (t.relkind IN ('v', 'm') AND k.prof >= 32)
          OR (t.relkind IN ('r', 'p')
              AND t.relrowsecurity
              AND k.lector IS NOT NULL
              AND (EXISTS (SELECT 1 FROM pg_catalog.pg_roles l
                            WHERE l.oid = k.lector AND (l.rolsuper OR l.rolbypassrls))
                   OR (pg_catalog.pg_has_role(k.lector, t.relowner, 'USAGE')
                       AND NOT t.relforcerowsecurity)))
    ) AS x;
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [VISTA_ELUDE_RLS] vista adicional accesible por la Data API que elude la RLS de tablas protegidas (Blueprint §7.3/§10): %.', v_txt;
  END IF;
  IF v_txt2 IS NOT NULL THEN
    RAISE WARNING 'validar_topologia: [PENDIENTE_DECISION_MATVIEW_RLS] vista materializada adicional accesible por la Data API que materializa datos de tablas con RLS leídos por un owner que la saltea; sin regla general aprobada, NO auditada: %.', v_txt2;
    v_pendientes := v_pendientes + 1;
  END IF;

  --     Otras relaciones adicionales de public (vista 'v', materializada 'm',
  --     foránea 'f'): ni el Blueprint ni ADR-001 fijan una regla general para
  --     ellas (el único contrato de vista expuesta es stock_actual). B11-03: no
  --     se rechazan ni se declaran seguras. Se informa, por relación, owner,
  --     security_invoker y los privilegios efectivos de anon, authenticated y
  --     service_role (incluye PUBLIC y membresías), separando las accesibles
  --     por la Data API como decisión pendiente de mayor riesgo.
  SELECT pg_catalog.string_agg(x.descr, ', ' ORDER BY x.relname, x.oid)
           FILTER (WHERE x.accesible_por IS NOT NULL),
         pg_catalog.string_agg(x.descr, ', ' ORDER BY x.relname, x.oid)
           FILTER (WHERE x.accesible_por IS NULL)
    INTO v_txt, v_txt2
    FROM (SELECT c.oid, c.relname,
                 'public.' || c.relname::pg_catalog.text || ' (oid ' || c.oid::pg_catalog.text
                 || ', relkind ' || c.relkind::pg_catalog.text
                 || ', owner ' || COALESCE(c.relowner::pg_catalog.regrole::pg_catalog.text, 'desconocido')
                 || ', security_invoker '
                 || CASE WHEN c.relkind <> 'v' THEN 'no_aplica'
                         ELSE COALESCE((SELECT o.option_value::pg_catalog.bool::pg_catalog.text
                                          FROM pg_catalog.pg_options_to_table(c.reloptions) AS o
                                         WHERE o.option_name = 'security_invoker'), 'false') END
                 || ', accesible por ' || COALESCE(a.accesible_por, 'ninguno') || ')' AS descr,
                 a.accesible_por
            FROM pg_catalog.pg_class c
            CROSS JOIN LATERAL (
              SELECT pg_catalog.string_agg(q.rol, '+' ORDER BY q.rol) AS accesible_por
                FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS q(rol)
               WHERE pg_catalog.has_table_privilege(q.rol, c.oid,
                       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
                  OR pg_catalog.has_any_column_privilege(q.rol, c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')) AS a
           WHERE c.relnamespace = v_oid_publico
             AND c.relkind IN ('v', 'm', 'f')
             AND c.oid IS DISTINCT FROM pg_catalog.to_regclass('public.stock_actual')::pg_catalog.oid) AS x;
  IF v_txt IS NOT NULL THEN
    RAISE WARNING 'validar_topologia: [PENDIENTE_DECISION_RELACION_ACCESIBLE] relaciones adicionales de public ACCESIBLES por la Data API, sin contrato aprobado; sin elusión de RLS detectada por dependencias, pero su definición NO está auditada: %.', v_txt;
    v_pendientes := v_pendientes + 1;
  END IF;
  IF v_txt2 IS NOT NULL THEN
    RAISE WARNING 'validar_topologia: [PENDIENTE_DECISION_RELACION] relaciones adicionales de public sin contrato aprobado y sin privilegios efectivos para anon, authenticated ni service_role; no se rechazan ni se declaran seguras: %.', v_txt2;
    v_pendientes := v_pendientes + 1;
  END IF;

  RAISE NOTICE 'validar_topologia: [T3P-05] owner postgres, RLS y sin FORCE en las 13 tablas expuestas; RLS y sin FORCE en toda tabla adicional de public (owner no validado); vista stock_actual conforme; ninguna vista adicional accesible elude la RLS según sus dependencias. Vistas, vistas materializadas y tablas foráneas adicionales: sin contrato auditado.';

  -- ======================================================
  -- 3. Funciones por firma exacta y OID (Bloque A: T3P-01..T3P-04, BA-01)
  -- ======================================================
  -- Manifiesto derivado de las migraciones y pruebas aprobadas. Cada función
  -- se resuelve por su firma exacta, calificada por esquema y con tipos
  -- pg_catalog (no se resuelve contra pg_temp), mediante to_regprocedure();
  -- el resto de las comprobaciones usa sólo ese OID. Nunca se busca por
  -- proname ni se condiciona un control a count(*) = 1.
  --
  -- Fuentes del contrato:
  --   * Auxiliares: 20261023140000 (usuario_actual), 20261029233000
  --     (empresa_gestion_actual), 20261105120000 (A1) y la línea de
  --     manifiesto de pg_temp_rpc_privilegiadas.test.sql P8 / B1.
  --   * Jornadas: 20261031120000, 20261101120000, 20261106120000..20261109120000
  --     y el manifiesto de 20261105130000 (B1).
  --   * Catálogos, implementaciones privadas: 20261023140000, 20261024144459,
  --     20261024180000 (owner, REVOKE/GRANT), 20261024232059 (P11) y
  --     pg_temp_catalogos.test.sql P8 (DEFINER, VOLATILE, propietario_rpc,
  --     search_path vacío, ACL exacta authenticated + propietario_rpc).
  --   * Catálogos, fachadas: mismas migraciones (language sql, volatile,
  --     security invoker, search_path = '', owner postgres, EXECUTE sólo
  --     para authenticated).
  --   * Stock (B.1.2a; ADR-001 §18.3): 20261025021032 (registrar_ingreso),
  --     20261025033454 (mover_a_cuarentena, registrar_merma) y 20261105120200
  --     (A3); contrato de stock_ingreso.test.sql:283-297,
  --     stock_cuarentena_merma.test.sql:174-227 y pg_temp_stock.test.sql:111-130.
  --
  -- Columnas: firma | nombre | esquema | owner | lenguaje | SECURITY DEFINER |
  --           volatilidad | ACL exacta ordenada | EXECUTE efectivo de
  --           authenticated (true = requerido, false = prohibido).
  -- Todas las filas exigen el contrato completo: owner, prokind = 'f',
  -- lenguaje, prosecdef, volatilidad, proconfig exacto, ACL exacta y
  -- privilegios efectivos (PUBLIC, anon y service_role sin EXECUTE;
  -- authenticated según la columna). No hay filas con contrato reducido.
  -- Cada rechazo indica el invariante violado entre corchetes.
  v_count := 0;
  FOR v_m IN
    SELECT *
      FROM (VALUES
        -- Auxiliares privados: authenticated NO ejecuta (pgTAP P8).
        ('privado.usuario_actual()',
         'usuario_actual', 'privado', 'propietario_rpc', 'sql', false, 's',
         'propietario_rpc=X/propietario_rpc', false),
        ('privado.empresa_gestion_actual()',
         'empresa_gestion_actual', 'privado', 'propietario_rpc', 'sql', true, 's',
         'propietario_rpc=X/propietario_rpc', false),

        -- Seis RPC de jornadas: 6 implementaciones privadas + 6 fachadas
        ('privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)',
         'abrir_jornada', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)',
         'abrir_jornada', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)',
         'reasignar_vendedor', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)',
         'reasignar_vendedor', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])',
         'registrar_carga', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])',
         'registrar_carga', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)',
         'registrar_descarga', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)',
         'registrar_descarga', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)',
         'confirmar_salida', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)',
         'confirmar_salida', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)',
         'corregir_jornada', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)',
         'corregir_jornada', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),

        -- Intenciones persistidas (ADR-010 v1.1, C1.2a): crear, ejecutar y cancelar (3 privadas + 3 fachadas)
        ('privado.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)',
         'crear_intencion_operacion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)',
         'crear_intencion_operacion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.ejecutar_intencion_operacion(pg_catalog.uuid)',
         'ejecutar_intencion_operacion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.ejecutar_intencion_operacion(pg_catalog.uuid)',
         'ejecutar_intencion_operacion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.cancelar_intencion_operacion(pg_catalog.uuid)',
         'cancelar_intencion_operacion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.cancelar_intencion_operacion(pg_catalog.uuid)',
         'cancelar_intencion_operacion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),

        -- Catálogos (BA-01 / T3P-01): 10 implementaciones privadas + 10 fachadas
        ('privado.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)',
         'crear_producto', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)',
         'crear_producto', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.actualizar_producto(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)',
         'actualizar_producto', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.actualizar_producto(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)',
         'actualizar_producto', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.cambiar_estado_producto(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_producto', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.cambiar_estado_producto(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_producto', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.crear_camion(pg_catalog.text, pg_catalog.text)',
         'crear_camion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.crear_camion(pg_catalog.text, pg_catalog.text)',
         'crear_camion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.actualizar_camion(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)',
         'actualizar_camion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.actualizar_camion(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)',
         'actualizar_camion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.cambiar_estado_camion(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_camion', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.cambiar_estado_camion(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_camion', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.crear_cliente(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)',
         'crear_cliente', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.crear_cliente(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)',
         'crear_cliente', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.actualizar_cliente(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)',
         'actualizar_cliente', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.actualizar_cliente(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)',
         'actualizar_cliente', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.validar_cliente(pg_catalog.uuid)',
         'validar_cliente', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.validar_cliente(pg_catalog.uuid)',
         'validar_cliente', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.cambiar_estado_cliente(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_cliente', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.cambiar_estado_cliente(pg_catalog.uuid, pg_catalog.bool)',
         'cambiar_estado_cliente', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),

        -- Stock (B.1.2a): 3 implementaciones privadas + 3 fachadas
        ('privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)',
         'registrar_ingreso', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)',
         'registrar_ingreso', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.mover_a_cuarentena(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)',
         'mover_a_cuarentena', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.mover_a_cuarentena(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)',
         'mover_a_cuarentena', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true),
        ('privado.registrar_merma(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text, pg_catalog.text)',
         'registrar_merma', 'privado', 'propietario_rpc', 'plpgsql', true, 'v',
         'authenticated=X/propietario_rpc,propietario_rpc=X/propietario_rpc', true),
        ('public.registrar_merma(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text, pg_catalog.text)',
         'registrar_merma', 'public', 'postgres', 'sql', false, 'v',
         'authenticated=X/postgres,postgres=X/postgres', true)
      ) AS m(firma, nombre, esquema, owner, lenguaje, secdef, volatilidad, acl, exec_authenticated)
  LOOP
    v_count := v_count + 1;

    -- 3.1 Firma exacta: si falta, rechazo explícito.
    v_oid_fn := pg_catalog.to_regprocedure(v_m.firma);
    IF v_oid_fn IS NULL THEN
      RAISE EXCEPTION 'validar_topologia: [FIRMA] falta la función con firma exacta %.', v_m.firma;
    END IF;

    SELECT p.proowner, l.lanname::pg_catalog.text, p.prokind::pg_catalog.text, p.prosecdef,
           p.provolatile::pg_catalog.text, p.proconfig,
           (SELECT pg_catalog.string_agg(a.acl::pg_catalog.text, ',' ORDER BY a.acl::pg_catalog.text)
              FROM pg_catalog.unnest(p.proacl) AS a(acl)),
           n.nspname::pg_catalog.text
      INTO v_owner_fn, v_lang_fn, v_kind_fn, v_secdef_fn,
           v_vol_fn, v_config_fn, v_acl_fn, v_distrib
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_language l ON l.oid = p.prolang
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE p.oid = v_oid_fn;

    IF v_distrib IS DISTINCT FROM v_m.esquema THEN
      RAISE EXCEPTION 'validar_topologia: [ESQUEMA] % (oid %) está en el esquema %, se esperaba %.',
        v_m.firma, v_oid_fn, v_distrib, v_m.esquema;
    END IF;

    -- 3.2 Privilegios efectivos. PUBLIC se evalúa sobre el ACL efectivo
    --     (proacl NULL = acldefault, que incluye EXECUTE para PUBLIC).
    IF EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc p,
             LATERAL pg_catalog.aclexplode(
               COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS e
       WHERE p.oid = v_oid_fn
         AND e.grantee = 0
         AND e.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'validar_topologia: [EXECUTE_PUBLIC] PUBLIC tiene EXECUTE sobre % (oid %).', v_m.firma, v_oid_fn;
    END IF;

    IF pg_catalog.has_function_privilege('service_role', v_oid_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'validar_topologia: [EXECUTE_SERVICE_ROLE] service_role tiene EXECUTE sobre % (oid %), que está denegado por defecto (P11 global).',
        v_m.firma, v_oid_fn;
    END IF;

    IF pg_catalog.has_function_privilege('anon', v_oid_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'validar_topologia: [EXECUTE_ANON] anon tiene EXECUTE sobre % (oid %).', v_m.firma, v_oid_fn;
    END IF;

    IF pg_catalog.has_function_privilege('authenticated', v_oid_fn, 'EXECUTE')
       IS DISTINCT FROM v_m.exec_authenticated THEN
      RAISE EXCEPTION 'validar_topologia: [EXECUTE_AUTHENTICATED] EXECUTE efectivo de authenticated sobre % (oid %) es %, el contrato exige %.',
        v_m.firma, v_oid_fn,
        pg_catalog.has_function_privilege('authenticated', v_oid_fn, 'EXECUTE'),
        v_m.exec_authenticated;
    END IF;

    -- 3.3 Contrato completo. Cada atributo se compara con IS DISTINCT FROM:
    --     un NULL nunca se acepta en silencio.
    IF v_owner_fn IS DISTINCT FROM (SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = v_m.owner) THEN
      RAISE EXCEPTION 'validar_topologia: [OWNER] % (oid %) tiene owner %, se esperaba %.',
        v_m.firma, v_oid_fn, pg_catalog.pg_get_userbyid(v_owner_fn), v_m.owner;
    END IF;

    IF v_kind_fn IS DISTINCT FROM 'f' THEN
      RAISE EXCEPTION 'validar_topologia: [PROKIND] % (oid %) tiene prokind %, se esperaba f.',
        v_m.firma, v_oid_fn, v_kind_fn;
    END IF;

    IF v_lang_fn IS DISTINCT FROM v_m.lenguaje THEN
      RAISE EXCEPTION 'validar_topologia: [LENGUAJE] % (oid %) usa el lenguaje %, se esperaba %.',
        v_m.firma, v_oid_fn, v_lang_fn, v_m.lenguaje;
    END IF;

    IF v_secdef_fn IS DISTINCT FROM v_m.secdef THEN
      RAISE EXCEPTION 'validar_topologia: [SECURITY] % (oid %) tiene prosecdef = %, el contrato exige % (%).',
        v_m.firma, v_oid_fn, v_secdef_fn, v_m.secdef,
        CASE WHEN v_m.secdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END;
    END IF;

    IF v_vol_fn IS DISTINCT FROM v_m.volatilidad THEN
      RAISE EXCEPTION 'validar_topologia: [VOLATILIDAD] % (oid %) tiene volatilidad %, se esperaba %.',
        v_m.firma, v_oid_fn, v_vol_fn, v_m.volatilidad;
    END IF;

    -- proconfig exacto: única entrada search_path vacío; ni NULL, ni
    -- entradas adicionales, ni otro valor de search_path.
    IF v_config_fn IS DISTINCT FROM ARRAY['search_path=""']::pg_catalog.text[] THEN
      RAISE EXCEPTION 'validar_topologia: [PROCONFIG] % (oid %) tiene proconfig %, se esperaba exactamente {search_path=""}.',
        v_m.firma, v_oid_fn, COALESCE(v_config_fn::pg_catalog.text, 'NULL');
    END IF;

    -- ACL exacta: NULL (acldefault), un grant extra o un grant faltante es rechazo.
    IF v_acl_fn IS DISTINCT FROM v_m.acl THEN
      RAISE EXCEPTION 'validar_topologia: [ACL] % (oid %) tiene ACL %, se esperaba %.',
        v_m.firma, v_oid_fn, COALESCE(v_acl_fn, 'NULL (acldefault)'), v_m.acl;
    END IF;

    IF v_m.secdef THEN
      v_sd_manifiesto := v_sd_manifiesto || v_oid_fn;
    END IF;
  END LOOP;

  IF v_count IS DISTINCT FROM 46 THEN
    RAISE EXCEPTION 'validar_topologia: [MANIFIESTO] el manifiesto de funciones debe tener 46 firmas, tiene %.', v_count;
  END IF;

  -- 3.4 Sin sobrecargas ni homónimos: para cada nombre del manifiesto, el
  --     conjunto de esquemas de TODAS las funciones con ese nombre (en
  --     cualquier esquema, incluido pg_temp_N) debe ser exactamente el
  --     esperado: una implementación en privado y, salvo los auxiliares, una
  --     fachada en public. Una sobrecarga agrega una entrada repetida y una
  --     copia en otro esquema agrega un esquema; ambas se rechazan.
  FOR v_m IN
    SELECT x.nombre,
           x.esperado,
           (SELECT pg_catalog.string_agg(n.nspname::pg_catalog.text, ',' ORDER BY n.nspname::pg_catalog.text)
              FROM pg_catalog.pg_proc p
              JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
             WHERE p.proname = x.nombre) AS real
      FROM (VALUES
        ('usuario_actual', 'privado'),
        ('empresa_gestion_actual', 'privado'),
        ('abrir_jornada', 'privado,public'),
        ('reasignar_vendedor', 'privado,public'),
        ('registrar_carga', 'privado,public'),
        ('registrar_descarga', 'privado,public'),
        ('confirmar_salida', 'privado,public'),
        ('corregir_jornada', 'privado,public'),
        ('crear_intencion_operacion', 'privado,public'),
        ('ejecutar_intencion_operacion', 'privado,public'),
        ('cancelar_intencion_operacion', 'privado,public'),
        ('crear_producto', 'privado,public'),
        ('actualizar_producto', 'privado,public'),
        ('cambiar_estado_producto', 'privado,public'),
        ('crear_camion', 'privado,public'),
        ('actualizar_camion', 'privado,public'),
        ('cambiar_estado_camion', 'privado,public'),
        ('crear_cliente', 'privado,public'),
        ('actualizar_cliente', 'privado,public'),
        ('validar_cliente', 'privado,public'),
        ('cambiar_estado_cliente', 'privado,public'),
        ('registrar_ingreso', 'privado,public'),
        ('mover_a_cuarentena', 'privado,public'),
        ('registrar_merma', 'privado,public'),
        -- O-4: public.rls_auto_enable() existe sólo en el proyecto alojado. Si
        -- existe, una única firma en public; si no, ninguna función con ese
        -- nombre en ningún esquema.
        ('rls_auto_enable', CASE WHEN pg_catalog.to_regprocedure('public.rls_auto_enable()') IS NULL
                                 THEN NULL ELSE 'public' END)
      ) AS x(nombre, esperado)
  LOOP
    IF v_m.real IS DISTINCT FROM v_m.esperado THEN
      RAISE EXCEPTION 'validar_topologia: [SOBRECARGA] sobrecarga u homónimo no autorizado de %: esquemas encontrados %, se esperaba %.',
        v_m.nombre, COALESCE(v_m.real, 'ninguno'), v_m.esperado;
    END IF;
  END LOOP;

  -- 3.5 Manifiesto exacto de los auxiliares (T3P-04). Misma línea y mismo
  --     mecanismo de hash que pg_temp_rpc_privilegiadas.test.sql (P8) y que
  --     el manifiesto de B1 (20261105130000): firma | owner | lenguaje |
  --     prokind | SECURITY DEFINER | leakproof | strict | retset | volatilidad
  --     | paralelismo | nargs | nargdefaults | tipo de retorno | nombres de
  --     argumentos | modos | support | costo | filas | proconfig | ACL
  --     ordenada | comentario | probin | prosqlbody nulo | SHA-256 de prosrc.
  --     Los valores esperados se copian literalmente de esas fuentes.
  FOR v_m IN
    SELECT x.firma, x.esperado,
           (SELECT p.oid::pg_catalog.regprocedure::pg_catalog.text
                   || '|' || p.proowner::pg_catalog.regrole::pg_catalog.text || '|' || l.lanname::pg_catalog.text
                   || '|' || p.prokind::pg_catalog.text
                   || '|' || p.prosecdef::pg_catalog.text || '|' || p.proleakproof::pg_catalog.text || '|' || p.proisstrict::pg_catalog.text
                   || '|' || p.proretset::pg_catalog.text || '|' || p.provolatile::pg_catalog.text || '|' || p.proparallel::pg_catalog.text
                   || '|' || p.pronargs::pg_catalog.text || '|' || p.pronargdefaults::pg_catalog.text
                   || '|' || p.prorettype::pg_catalog.regtype::pg_catalog.text
                   || '|' || COALESCE(p.proargnames::pg_catalog.text, '-') || '|' || COALESCE(p.proargmodes::pg_catalog.text, '-')
                   || '|' || COALESCE(NULLIF(p.prosupport::pg_catalog.oid, 0::pg_catalog.oid)::pg_catalog.text, '-')
                   || '|' || p.procost::pg_catalog.text || '|' || p.prorows::pg_catalog.text
                   || '|' || COALESCE(p.proconfig::pg_catalog.text, '-')
                   || '|' || COALESCE(pg_catalog.array_to_string(
                               ARRAY(SELECT a::pg_catalog.text FROM pg_catalog.unnest(p.proacl) a ORDER BY 1), ','), '-')
                   || '|' || COALESCE(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')
                   || '|' || COALESCE(p.probin, '-')
                   || '|' || (p.prosqlbody IS NULL)::pg_catalog.text
                   || '|' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
              FROM pg_catalog.pg_proc p
              JOIN pg_catalog.pg_language l ON l.oid = p.prolang
             WHERE p.oid = pg_catalog.to_regprocedure(x.firma)) AS real
      FROM (VALUES
        ('privado.usuario_actual()',
         'privado.usuario_actual()|propietario_rpc|sql|f|false|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|2ab0212d86923d76b38887c88af3470c5ae5732f434ed587b23535ddeeb2ed96'),
        ('privado.empresa_gestion_actual()',
         'privado.empresa_gestion_actual()|propietario_rpc|sql|f|true|false|false|false|s|u|0|0|uuid|-|-|-|100|0|{"search_path=\"\""}|propietario_rpc=X/propietario_rpc|-|-|true|6d0a758d68ffaf8f575e1faebb132dc29cab4400e81c953b6dc73ed475fce7cc')
      ) AS x(firma, esperado)
  LOOP
    IF v_m.real IS DISTINCT FROM v_m.esperado THEN
      RAISE EXCEPTION 'validar_topologia: [MANIFIESTO_AUXILIAR] % no coincide con el contrato aprobado (B1 / pgTAP P8). Real: %. Esperado: %.',
        v_m.firma, COALESCE(v_m.real, 'NULL (firma ausente)'), v_m.esperado;
    END IF;
  END LOOP;

  -- 3.6 BA2-01: privilegios efectivos de los auxiliares para lector_perfiles_rpc
  --     y postgres (contrato P8/P11 de pg_temp_rpc_privilegiadas.test.sql:
  --     ni anon, authenticated, service_role, lector_perfiles_rpc ni postgres
  --     ejecutan los auxiliares). Control efectivo con has_function_privilege
  --     sobre el OID de la firma exacta: detecta EXECUTE obtenido por
  --     membresía heredada aunque la ACL de la función no cambie. PUBLIC,
  --     anon, authenticated y service_role ya se verifican en 3.2.
  --     Se acumulan todas las violaciones y se informan juntas.
  v_violaciones := NULL;
  FOR v_m IN
    SELECT f.firma, r.rol
      FROM (VALUES ('privado.usuario_actual()'), ('privado.empresa_gestion_actual()')) AS f(firma),
           (VALUES ('lector_perfiles_rpc'), ('postgres')) AS r(rol)
     ORDER BY f.firma, r.rol
  LOOP
    v_oid_fn := pg_catalog.to_regprocedure(v_m.firma);
    IF v_oid_fn IS NULL THEN
      RAISE EXCEPTION 'validar_topologia: [FIRMA] falta la función con firma exacta %.', v_m.firma;
    END IF;

    IF pg_catalog.has_function_privilege(v_m.rol::pg_catalog.name, v_oid_fn, 'EXECUTE') THEN
      v_violaciones := COALESCE(v_violaciones || ', ', '')
                   || v_m.rol || ' sobre ' || v_m.firma || ' (oid ' || v_oid_fn::pg_catalog.text || ')';
    END IF;
  END LOOP;

  IF v_violaciones IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [EXECUTE_EFECTIVO_AUXILIAR] EXECUTE efectivo prohibido en auxiliares: %.', v_violaciones;
  END IF;

  -- 3.7 B.1.2a — Inventario exhaustivo de funciones SECURITY DEFINER
  --     (ADR-001 §17.3: «ninguna función SECURITY DEFINER fuera de la lista
  --     aprobada»; P4: viven en privado). Esquemas de aplicación: public,
  --     privado y graphql_public (expuesto en supabase/config.toml). Identidad
  --     por OID resuelto desde la firma exacta, nunca por nombre. La única
  --     excepción es public.rls_auto_enable() con el contrato completo de O-4
  --     (§18.2; hardening_adr001.test.sql:348-398). Autorización humana del
  --     inventario: 05/11/2026 (B.1.2a).
  v_oid_graphql_public := pg_catalog.to_regnamespace('graphql_public');

  SELECT pg_catalog.array_agg(pg_catalog.to_regprocedure(f.firma)::pg_catalog.oid ORDER BY f.firma),
         pg_catalog.string_agg(f.firma, ', ' ORDER BY f.firma)
           FILTER (WHERE pg_catalog.to_regprocedure(f.firma) IS NULL)
    INTO v_sd_aprobadas, v_txt
    FROM (VALUES
      ('privado.empresa_gestion_actual()'),
      ('privado.crear_producto(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)'),
      ('privado.actualizar_producto(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.numeric, pg_catalog.int4)'),
      ('privado.cambiar_estado_producto(pg_catalog.uuid, pg_catalog.bool)'),
      ('privado.crear_camion(pg_catalog.text, pg_catalog.text)'),
      ('privado.actualizar_camion(pg_catalog.uuid, pg_catalog.text, pg_catalog.text)'),
      ('privado.cambiar_estado_camion(pg_catalog.uuid, pg_catalog.bool)'),
      ('privado.crear_cliente(pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)'),
      ('privado.actualizar_cliente(pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.text)'),
      ('privado.validar_cliente(pg_catalog.uuid)'),
      ('privado.cambiar_estado_cliente(pg_catalog.uuid, pg_catalog.bool)'),
      ('privado.registrar_ingreso(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)'),
      ('privado.mover_a_cuarentena(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text)'),
      ('privado.registrar_merma(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid, pg_catalog.int4, pg_catalog.text, pg_catalog.text)'),
      ('privado.abrir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid)'),
      ('privado.reasignar_vendedor(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)'),
      ('privado.registrar_carga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[])'),
      ('privado.registrar_descarga(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid[], pg_catalog.int4[], pg_catalog.text)'),
      ('privado.confirmar_salida(pg_catalog.uuid, pg_catalog.uuid)'),
      ('privado.corregir_jornada(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.date, pg_catalog.uuid, pg_catalog.text)'),
      ('privado.crear_intencion_operacion(pg_catalog.uuid, pg_catalog.text, pg_catalog.jsonb)'),
      ('privado.ejecutar_intencion_operacion(pg_catalog.uuid)'),
      ('privado.cancelar_intencion_operacion(pg_catalog.uuid)')
    ) AS f(firma);

  IF v_txt IS NOT NULL OR pg_catalog.cardinality(v_sd_aprobadas) IS DISTINCT FROM 23 THEN
    RAISE EXCEPTION 'validar_topologia: [SD_INVENTARIO] faltan funciones SECURITY DEFINER aprobadas: %.',
      COALESCE(v_txt, 'cardinalidad distinta de 23');
  END IF;

  --     Coherencia con el manifiesto: los miembros del inventario son
  --     exactamente las filas SECURITY DEFINER del manifiesto, cuyo contrato
  --     completo (owner, lenguaje, volatilidad, proconfig, ACL y EXECUTE) ya se
  --     verificó en 3.1-3.3.
  IF pg_catalog.cardinality(v_sd_manifiesto) IS DISTINCT FROM 23
     OR NOT (v_sd_manifiesto @> v_sd_aprobadas AND v_sd_aprobadas @> v_sd_manifiesto) THEN
    RAISE EXCEPTION 'validar_topologia: [SD_INVENTARIO] el inventario SECURITY DEFINER (%) no coincide con las filas SECURITY DEFINER del manifiesto (%).',
      pg_catalog.cardinality(v_sd_aprobadas), pg_catalog.cardinality(v_sd_manifiesto);
  END IF;

  --     Excepción O-4. Su existencia y la revocación de EXECUTE provienen de
  --     ADR-001 §18.2 VIGENTE; el contrato exacto que se exige abajo es el
  --     RB + RA, APROBADO SÓLO COMO NORMA (ADR-001 §18.2.1; ver la cabecera
  --     de DECLARE; el contrato histórico B.1.2b/B.1.2c, 325ae266…, ya no
  --     se acepta):
  --       función: SECURITY DEFINER, prokind f, owner postgres, retorno
  --         event_trigger, proconfig exacto {search_path=pg_catalog, pg_temp},
  --         sin EXECUTE para PUBLIC/anon/authenticated/service_role, ACL
  --         exacta {postgres=X/postgres} (E-O4-ACL, aprobada por decisión
  --         humana para LOCAL; ADR-001 §18.2.2), lenguaje
  --         plpgsql, prosqlbody y probin nulos y SHA-256 de prosrc igual a
  --         v_o4_sha256_prosrc;
  --       event trigger: ensure_rls único y asociado en forma exclusiva a la
  --         función (ningún otro event trigger ni trigger de tabla la usa),
  --         owner postgres, evento ddl_command_end, evtenabled = 'O' y tags
  --         exactamente {CREATE TABLE, CREATE TABLE AS, SELECT INTO}: tres
  --         tags distintas, en cualquier orden, sin duplicados ni NULL.
  --     Se acumulan todas las violaciones en un único mensaje. La identidad
  --     va por OID; evtfoid nunca se compara con un literal.
  v_oid_fn := pg_catalog.to_regprocedure('public.rls_auto_enable()');
  IF v_oid_fn IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_class m
                WHERE m.relnamespace = pg_catalog.pg_my_temp_schema()
                  AND m.relname = v_marc_nombre::pg_catalog.name) THEN
      RAISE EXCEPTION 'validar_topologia: [O4_MARCADOR_INVALIDO] el marcador de laboratorio pg_temp.% existe pero O-4 está presente: el marcador sólo es válido con O-4 ausente.', v_marc_nombre;
    END IF;
    SELECT NULLIF(pg_catalog.concat_ws('; ',
             CASE WHEN NOT p.prosecdef THEN 'no es SECURITY DEFINER' END,
             CASE WHEN p.prokind <> 'f' THEN 'prokind ' || p.prokind::pg_catalog.text END,
             CASE WHEN p.proowner <> v_oid_postgres
                  THEN 'owner ' || COALESCE(pg_catalog.pg_get_userbyid(p.proowner)::pg_catalog.text, 'desconocido') END,
             CASE WHEN p.prorettype <> 'pg_catalog.event_trigger'::pg_catalog.regtype
                  THEN 'retorno ' || p.prorettype::pg_catalog.regtype::pg_catalog.text END,
             CASE WHEN p.proconfig IS DISTINCT FROM v_o4_proconfig
                  THEN 'proconfig ' || COALESCE(p.proconfig::pg_catalog.text, 'NULL') END,
             CASE WHEN EXISTS (SELECT 1
                                 FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS e
                                WHERE e.grantee = 0 AND e.privilege_type = 'EXECUTE')
                  THEN 'EXECUTE para PUBLIC' END,
             CASE WHEN pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'EXECUTE efectivo anon' END,
             CASE WHEN pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'EXECUTE efectivo authenticated' END,
             CASE WHEN pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') THEN 'EXECUTE efectivo service_role' END,
             --   E-O4-ACL (ADR-001 §18.2.2, sólo LOCAL): la ACL tiene que ser
             --   exactamente {postgres=X/postgres}: una única entrada, otorgante
             --   y beneficiario postgres, sólo EXECUTE y sin opción de delegación.
             --   Fail-closed: proacl NULL (ACL por defecto, que incluye PUBLIC),
             --   un arreglo vacío, cualquier entrada adicional o WITH GRANT
             --   OPTION son defecto. No se extiende a otras funciones.
             CASE WHEN p.proacl IS NULL
                    OR pg_catalog.array_ndims(p.proacl) IS DISTINCT FROM 1
                    OR pg_catalog.array_length(p.proacl, 1) IS DISTINCT FROM 1
                    OR (SELECT pg_catalog.count(*) FROM pg_catalog.aclexplode(p.proacl)) IS DISTINCT FROM 1
                    OR NOT EXISTS (SELECT 1
                                     FROM pg_catalog.aclexplode(p.proacl) AS ex
                                    WHERE ex.grantor = v_oid_postgres
                                      AND ex.grantee = v_oid_postgres
                                      AND ex.privilege_type = 'EXECUTE'
                                      AND NOT ex.is_grantable)
                  THEN 'ACL distinta de {postgres=X/postgres} (E-O4-ACL; ACL actual: '
                       || COALESCE(p.proacl::pg_catalog.text, 'NULL') || ')' END,
             CASE WHEN l.lanname::pg_catalog.text IS DISTINCT FROM v_o4_lenguaje
                  THEN 'lenguaje ' || l.lanname::pg_catalog.text END,
             CASE WHEN p.prosqlbody IS NOT NULL OR p.probin IS NOT NULL THEN 'prosqlbody/probin no nulos' END,
             CASE WHEN pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex')
                       IS DISTINCT FROM v_o4_sha256_prosrc
                  THEN 'cuerpo distinto del contrato RB + RA propuesto (sha256 '
                       || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc, 'UTF8')), 'hex') || ')' END
           ), '')
      INTO v_o4_funcion
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_language l ON l.oid = p.prolang
     WHERE p.oid = v_oid_fn;

    --   Toda fila de pg_event_trigger llamada ensure_rls o que apunte a la
    --   función tiene que ser ensure_rls con el contrato completo.
    SELECT pg_catalog.string_agg(x.evtname || ' (oid ' || x.oid::pg_catalog.text || '): ' || x.det, '; '
                                 ORDER BY x.evtname, x.oid) FILTER (WHERE x.det <> ''),
           pg_catalog.count(*) FILTER (WHERE x.evtname = 'ensure_rls' AND x.evtfoid = v_oid_fn)
      INTO v_o4_triggers, v_o4_n_ensure
      FROM (SELECT t.oid, t.evtname::pg_catalog.text AS evtname, t.evtfoid,
                   pg_catalog.concat_ws(', ',
                     CASE WHEN t.evtname <> 'ensure_rls' THEN 'event trigger adicional sobre la función' END,
                     CASE WHEN t.evtfoid <> v_oid_fn
                          THEN 'apunta a ' || COALESCE(
                                 (SELECT pg_catalog.quote_ident(n.nspname::pg_catalog.text) || '.'
                                         || pg_catalog.quote_ident(p.proname::pg_catalog.text) || '('
                                         || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
                                    FROM pg_catalog.pg_proc p
                                    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
                                   WHERE p.oid = t.evtfoid),
                                 'oid ' || t.evtfoid::pg_catalog.text) END,
                     CASE WHEN t.evtowner <> v_oid_postgres
                          THEN 'owner ' || COALESCE(pg_catalog.pg_get_userbyid(t.evtowner)::pg_catalog.text, 'desconocido') END,
                     CASE WHEN t.evtevent <> 'ddl_command_end' THEN 'evento ' || t.evtevent::pg_catalog.text END,
                     CASE WHEN t.evtenabled <> 'O' THEN 'evtenabled ' || t.evtenabled::pg_catalog.text END,
                     --   B.1.2c (B12B-01): igualdad exacta como multiconjunto,
                     --   independiente del orden: se ordenan los elementos
                     --   (collation C, NULL al final) y se comparan con la
                     --   referencia ordenada. Rechaza duplicadas, faltantes,
                     --   sobrantes, NULL (array o elemento) y arrays no 1-D.
                     CASE WHEN t.evttags IS NULL
                            OR pg_catalog.array_ndims(t.evttags) IS DISTINCT FROM 1
                            OR ARRAY(SELECT u.tag
                                       FROM pg_catalog.unnest(t.evttags) AS u(tag)
                                      ORDER BY u.tag COLLATE pg_catalog."C")
                               IS DISTINCT FROM ARRAY['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::pg_catalog.text[]
                          THEN 'tags ' || COALESCE(t.evttags::pg_catalog.text, 'NULL (todos los comandos)') END
                   ) AS det
              FROM pg_catalog.pg_event_trigger t
             WHERE t.evtname = 'ensure_rls' OR t.evtfoid = v_oid_fn) AS x;

    --   Defensa redundante (ADR §18.2: «ningún trigger de tabla la usa»).
    v_o4_trg_tabla := EXISTS (SELECT 1 FROM pg_catalog.pg_trigger tg WHERE tg.tgfoid = v_oid_fn);

    IF v_o4_funcion IS NOT NULL OR v_o4_triggers IS NOT NULL
       OR v_o4_n_ensure IS DISTINCT FROM 1 OR v_o4_trg_tabla THEN
      RAISE EXCEPTION 'validar_topologia: [O4_RLS_AUTO_ENABLE] public.rls_auto_enable() (oid %) fuera del contrato O-4: %.',
        v_oid_fn,
        pg_catalog.concat_ws(' | ',
          'función: ' || v_o4_funcion,
          'event triggers: ' || v_o4_triggers,
          CASE WHEN v_o4_n_ensure IS DISTINCT FROM 1 THEN 'no existe ensure_rls asociado a la función' END,
          CASE WHEN v_o4_trg_tabla THEN 'un trigger de tabla usa la función' END);
    END IF;
    v_sd_aprobadas := v_sd_aprobadas || v_oid_fn;
  ELSIF EXISTS (SELECT 1 FROM pg_catalog.pg_event_trigger t WHERE t.evtname = 'ensure_rls') THEN
    RAISE EXCEPTION 'validar_topologia: [O4_RLS_AUTO_ENABLE] existe el event trigger ensure_rls sin public.rls_auto_enable() (O-4: presentes o ausentes juntos).';
  ELSE
    -- M-01: faltan a la vez la función y ensure_rls. Modo estricto por
    -- defecto: es un rechazo, salvo marcador explícito de laboratorio local.
    -- Marcador: tabla TEMPORAL de la propia sesión pg_temp.<v_marc_nombre>,
    -- relkind 'r', relpersistence 't', no partición, sin herencia, con una
    -- única columna activa «modo» de tipo text y exactamente una fila cuyo
    -- valor es v_marc_valor. Cualquier otra forma se rechaza. El catálogo se
    -- consulta con pg_my_temp_schema() (nunca por search_path) y el operador
    -- de comparación va calificado.
    SELECT c.oid, n.nspname::pg_catalog.text
      INTO v_marc_oid, v_marc_nsp
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relnamespace = pg_catalog.pg_my_temp_schema()
       AND c.relname = v_marc_nombre::pg_catalog.name;
    IF v_marc_oid IS NULL THEN
      RAISE EXCEPTION 'validar_topologia: [O4_AUSENTE] public.rls_auto_enable() y ensure_rls están ausentes y no hay marcador de laboratorio local (tabla temporal pg_temp.%). Modo estricto: el entorno alojado debe conservar O-4 (ADR-001 §18.2).', v_marc_nombre;
    END IF;
    SELECT pg_catalog.concat_ws('; ',
             CASE WHEN c.relkind <> 'r' THEN 'relkind ' || c.relkind::pg_catalog.text END,
             CASE WHEN c.relpersistence <> 't' THEN 'no es temporal' END,
             CASE WHEN c.relispartition OR c.relhassubclass
                    OR EXISTS (SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid = c.oid OR i.inhparent = c.oid)
                  THEN 'partición o herencia' END,
             CASE WHEN (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute a
                         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) <> 1
                    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                                    WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                                      AND a.attname = 'modo'
                                      AND a.atttypid = 'pg_catalog.text'::pg_catalog.regtype)
                  THEN 'estructura distinta de (modo text)' END)
      INTO v_marc_err
      FROM pg_catalog.pg_class c
     WHERE c.oid = v_marc_oid;
    IF v_marc_err <> '' THEN
      RAISE EXCEPTION 'validar_topologia: [O4_MARCADOR_INVALIDO] el marcador pg_temp.% no cumple la estructura: %.', v_marc_nombre, v_marc_err;
    END IF;
    EXECUTE pg_catalog.format(
      'SELECT pg_catalog.count(*), pg_catalog.count(*) FILTER (WHERE modo OPERATOR(pg_catalog.=) %L) FROM %I.%I',
      v_marc_valor, v_marc_nsp, v_marc_nombre)
      INTO v_marc_filas, v_marc_ok;
    IF v_marc_filas IS DISTINCT FROM 1 OR v_marc_ok IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'validar_topologia: [O4_MARCADOR_INVALIDO] el marcador pg_temp.% debe contener exactamente una fila con modo = % (filas: %, válidas: %).',
        v_marc_nombre, v_marc_valor, v_marc_filas, v_marc_ok;
    END IF;
    v_modo_local := true;
    RAISE WARNING 'validar_topologia: [O4_AUSENTE_LABORATORIO] O-4 ausente aceptado SOLO por el marcador explícito de laboratorio local. Este resultado nunca es ESTADO_A y no sirve para staging ni producción.';
  END IF;

  --     Rechazo exhaustivo: toda función SECURITY DEFINER (cualquier prokind)
  --     de public, privado o graphql_public cuyo OID no pertenezca al conjunto
  --     aprobado, cualquiera sea su nombre, owner o privilegios.
  SELECT pg_catalog.string_agg(
           pg_catalog.quote_ident(n.nspname::pg_catalog.text) || '.'
           || pg_catalog.quote_ident(p.proname::pg_catalog.text)
           || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
           || ' oid ' || p.oid::pg_catalog.text
           || ' prokind ' || p.prokind::pg_catalog.text
           || ' owner ' || COALESCE(pg_catalog.pg_get_userbyid(p.proowner)::pg_catalog.text, 'desconocido')
           || ' EXECUTE[PUBLIC=' || (EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS e
                                             WHERE e.grantee = 0 AND e.privilege_type = 'EXECUTE'))::pg_catalog.text
           || ',anon=' || pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')::pg_catalog.text
           || ',authenticated=' || pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')::pg_catalog.text
           || ',service_role=' || pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')::pg_catalog.text || ']',
           '; ' ORDER BY n.nspname, p.proname, p.oid)
    INTO v_txt
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prosecdef
     AND (p.pronamespace = v_oid_publico
          OR p.pronamespace = v_oid_privado
          OR p.pronamespace IS NOT DISTINCT FROM v_oid_graphql_public)
     AND p.oid <> ALL (v_sd_aprobadas);
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [SD_NO_AUTORIZADA] funciones SECURITY DEFINER fuera del inventario aprobado (ADR-001 §17.3, P4): %.', v_txt;
  END IF;

  RAISE NOTICE 'validar_topologia: verificación de funciones por firma exacta y OID exitosa (46 firmas con contrato completo, sin sobrecargas, manifiesto de auxiliares conforme; inventario SECURITY DEFINER exhaustivo de 23 firmas%).',
    CASE WHEN pg_catalog.to_regprocedure('public.rls_auto_enable()') IS NULL THEN '' ELSE ' + excepción O-4' END;

  -- ======================================================
  -- 4. T3P-08: service_role y la excepción P11-productos (conjunto exacto)
  -- ======================================================
  -- Contrato: ADR-001 §18.1 (P11-productos) y §18.2 (P11 global): denegado
  -- por defecto; única excepción SELECT sobre public.productos, que no
  -- autoriza INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  -- ni EXECUTE. Tests: hardening_adr001.test.sql (P11) y
  -- grants_default_privileges.test.sql (O-1). Se usan privilegios efectivos
  -- (incluyen PUBLIC y membresías heredadas) y ACL explícitas, por separado
  -- para tablas, columnas, funciones y esquemas. No se extiende a objetos
  -- internos del stack Supabase.

  -- 4.1 Tablas: privilegio efectivo exacto (13 tablas x 8 privilegios).
  SELECT pg_catalog.string_agg(p.priv || ' ' || t.tabla || '=' ||
           pg_catalog.has_table_privilege('service_role', pg_catalog.to_regclass(t.tabla), p.priv)::pg_catalog.text,
           ', ' ORDER BY t.tabla, p.priv)
    INTO v_txt
    FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                 ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                 ('public.operaciones'), ('public.movimientos_stock'),
                 ('public.jornadas'), ('public.reasignaciones_vendedor'),
                 ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) AS t(tabla),
         (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                 ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) AS p(priv)
   WHERE pg_catalog.has_table_privilege('service_role', pg_catalog.to_regclass(t.tabla), p.priv)
         IS DISTINCT FROM (t.tabla = 'public.productos' AND p.priv = 'SELECT');
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_TABLA] privilegio efectivo de service_role fuera de la excepción P11 (privilegio tabla=real): %.', v_txt;
  END IF;

  --     Vistas expuesta y privada: ningún privilegio efectivo.
  SELECT pg_catalog.string_agg(t.rel, ', ' ORDER BY t.rel) INTO v_txt
    FROM (VALUES ('public.stock_actual'), ('privado.perfiles_empresa_gestion')) AS t(rel)
   WHERE pg_catalog.has_table_privilege('service_role', pg_catalog.to_regclass(t.rel),
           'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN');
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_TABLA] service_role tiene privilegios sobre: %.', v_txt;
  END IF;

  -- 4.2 ACL explícita de tabla: productos otorga a service_role exactamente
  --     SELECT sin GRANT OPTION; ninguna otra relación de public o privado lo
  --     nombra.
  SELECT pg_catalog.string_agg(a.privilege_type || CASE WHEN a.is_grantable THEN '*' ELSE '' END,
                               ',' ORDER BY a.privilege_type)
    INTO v_txt
    FROM pg_catalog.pg_class c, LATERAL pg_catalog.aclexplode(c.relacl) a
   WHERE c.oid = pg_catalog.to_regclass('public.productos') AND a.grantee = v_oid_service_role;
  IF v_txt IS DISTINCT FROM 'SELECT' THEN
    RAISE EXCEPTION 'validar_topologia: [P11_ACL_TABLA] la ACL de public.productos le da a service_role %, se esperaba exactamente SELECT.', COALESCE(v_txt, 'nada');
  END IF;

  SELECT pg_catalog.string_agg(n.nspname::pg_catalog.text || '.' || c.relname::pg_catalog.text, ', ' ORDER BY 1)
    INTO v_txt
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace,
         LATERAL pg_catalog.aclexplode(c.relacl) a
   WHERE c.relnamespace IN (v_oid_publico, v_oid_privado)
     AND c.oid <> pg_catalog.to_regclass('public.productos')
     AND a.grantee = v_oid_service_role;
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_ACL_TABLA] service_role figura en la ACL de: %.', v_txt;
  END IF;

  -- 4.3 Columnas: sin INSERT/UPDATE/REFERENCES por columna; SELECT por
  --     columna sólo en productos; sin entradas attacl para service_role.
  SELECT pg_catalog.string_agg(t.tabla, ', ' ORDER BY t.tabla) INTO v_txt
    FROM (VALUES ('public.empresas'), ('public.perfiles'), ('public.productos'),
                 ('public.camiones'), ('public.clientes'), ('public.ubicaciones'),
                 ('public.operaciones'), ('public.movimientos_stock'),
                 ('public.jornadas'), ('public.reasignaciones_vendedor'),
                 ('public.correcciones_jornada'), ('public.intenciones_operacion'), ('public.intenciones_reconocimientos')) AS t(tabla)
   WHERE pg_catalog.has_any_column_privilege('service_role', pg_catalog.to_regclass(t.tabla), 'INSERT, UPDATE, REFERENCES')
      OR (t.tabla <> 'public.productos'
          AND pg_catalog.has_any_column_privilege('service_role', pg_catalog.to_regclass(t.tabla), 'SELECT'));
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_COLUMNA] service_role tiene privilegios por columna no autorizados sobre: %.', v_txt;
  END IF;

  SELECT pg_catalog.string_agg(c.relname::pg_catalog.text || '.' || at.attname::pg_catalog.text, ', ' ORDER BY 1)
    INTO v_txt
    FROM pg_catalog.pg_attribute at
    JOIN pg_catalog.pg_class c ON c.oid = at.attrelid,
         LATERAL pg_catalog.aclexplode(at.attacl) a
   WHERE c.relnamespace IN (v_oid_publico, v_oid_privado)
     AND a.grantee = v_oid_service_role;
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_ACL_COLUMNA] service_role figura en la ACL de columnas: %.', v_txt;
  END IF;

  -- 4.4 Funciones: ningún EXECUTE efectivo ni entrada de ACL en public o privado.
  SELECT pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::pg_catalog.text, ', ' ORDER BY 1)
    INTO v_txt
    FROM pg_catalog.pg_proc p
   WHERE p.pronamespace IN (v_oid_publico, v_oid_privado)
     AND pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE');
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [P11_FUNCION] service_role tiene EXECUTE efectivo sobre: %.', v_txt;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p, LATERAL pg_catalog.aclexplode(p.proacl) a
              WHERE p.pronamespace IN (v_oid_publico, v_oid_privado)
                AND a.grantee = v_oid_service_role) THEN
    RAISE EXCEPTION 'validar_topologia: [P11_ACL_FUNCION] service_role figura en la ACL de una función de public o privado.';
  END IF;

  -- 4.5 Esquemas: sin CREATE en public/privado y sin USAGE en privado.
  IF pg_catalog.has_schema_privilege('service_role', 'public', 'CREATE')
     OR pg_catalog.has_schema_privilege('service_role', 'privado', 'CREATE')
     OR pg_catalog.has_schema_privilege('service_role', 'privado', 'USAGE') THEN
    RAISE EXCEPTION 'validar_topologia: [P11_ESQUEMA] service_role tiene CREATE en public/privado o USAGE en privado.';
  END IF;

  RAISE NOTICE 'validar_topologia: [T3P-08] service_role conforme a P11 (sólo SELECT sobre public.productos).';

  -- ======================================================
  -- 5. T3P-06: manifiesto exacto de políticas RLS
  -- ======================================================
  -- Contrato: las 38 políticas (33 previas + 5 de ADR-010 C1.1: 3 de intenciones_operacion
  -- y 2 de intenciones_reconocimientos, migración 20261111120000) creadas o modificadas por las migraciones
  -- 20261022120000, 20261023140000, 20261024144459, 20261024180000,
  -- 20261025010315, 20261025021032, 20261025033454 (ALTER POLICY),
  -- 20261029233000 y 20261030120000 (CREATE/ALTER POLICY); nombres, comandos
  -- y roles coinciden con jornadas_esquema.test.sql y lector_perfiles_rpc.test.sql.
  -- Representación estable de las expresiones: pg_get_expr(polqual|polwithcheck,
  -- polrelid), el mismo deparse que comparan 20261029233000 y 20261030120000,
  -- con search_path fijo 'pg_catalog, pg_temp' (pg_get_expr omite el esquema
  -- de lo visible en el search_path, así que se fija para que el texto no
  -- dependa de la sesión). Se compara su SHA-256; el texto completo de cada
  -- expresión está en la evidencia del Bloque B. '-' = expresión ausente.
  -- polcmd: r SELECT, a INSERT, w UPDATE, d DELETE, * ALL.
  v_search_path_previo := pg_catalog.current_setting('search_path');
  PERFORM pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  v_politicas := ARRAY[]::pg_catalog.text[];
  v_rels_manifiesto := ARRAY[]::pg_catalog.oid[];
  FOR v_b IN
    SELECT *
      FROM (VALUES
        ('public.camiones', 'camiones_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '31dfcc826f04640eb45b76352e59e7077e9e529aaab512575616864ca8abed4c'),
        ('public.camiones', 'camiones_select_empresa', 'r', true, 'authenticated', '98d21a529dd4c28e9cf89b0a9d0bda5812b509327bac1180d0553c8d41b5e860', '-'),
        ('public.camiones', 'camiones_select_propietario_rpc', 'r', true, 'propietario_rpc', '760c31fdb54a59bfc1ef6f39e4e06a4e7fa04da4d387c69153f09eef4a623c19', '-'),
        ('public.camiones', 'camiones_update_propietario_rpc', 'w', true, 'propietario_rpc', '4810d2c450c8b553cfb607a5cf08f75891c98eed7b5057587b0b79d43b9295b3', '4810d2c450c8b553cfb607a5cf08f75891c98eed7b5057587b0b79d43b9295b3'),
        ('public.clientes', 'clientes_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', 'e8a025f675b039482930d502127397bc83e2ae8525ea55442ffa9ce94b5f3c99'),
        ('public.clientes', 'clientes_select_empresa', 'r', true, 'authenticated', '06d05ae5cf0118d6ca456a9e65b643e1943537b865c215a943a851508ef1a090', '-'),
        ('public.clientes', 'clientes_select_propietario_rpc', 'r', true, 'propietario_rpc', 'c0ed29fdabcce61fe98508138bd8bd38a349ad8fc80ba9061589723e76d1d1cc', '-'),
        ('public.clientes', 'clientes_update_propietario_rpc', 'w', true, 'propietario_rpc', '72f34be3e5e60157d13d84184911c3df004df522a148710cccdf2bd9116ebb70', '72f34be3e5e60157d13d84184911c3df004df522a148710cccdf2bd9116ebb70'),
        ('public.correcciones_jornada', 'correcciones_jornada_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', 'c5d795ed65bf2f068c9805803fd90a1de86a8086fa58c7aa331e96d21009bef9'),
        ('public.correcciones_jornada', 'correcciones_jornada_select_gestion', 'r', true, 'authenticated', 'e2cab0d2f56875654114598fae11fe8d4de6859df9515a02bf781154824b7ace', '-'),
        ('public.empresas', 'empresas_select_propia', 'r', true, 'authenticated', '8083139157ef6916662d922328806be0baa81de21be1c04decb7763c47c7d128', '-'),
        ('public.intenciones_operacion', 'intenciones_operacion_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '1a8a0e8bffa9f1ac18c15a92580f8345d16275f4613bfc7545cece87d24da13e'),
        ('public.intenciones_operacion', 'intenciones_operacion_select_propietario_rpc', 'r', true, 'propietario_rpc', '1a8a0e8bffa9f1ac18c15a92580f8345d16275f4613bfc7545cece87d24da13e', '-'),
        ('public.intenciones_operacion', 'intenciones_operacion_update_propietario_rpc', 'w', true, 'propietario_rpc', '69fec85de1026b60d96e011dc5fe329cfb8a42d4ac139543c1fa86431b9c1849', 'ac98a486361edc7027558c5eb6fc3abd301aba44a292bdb8dd8badac224e04c1'),
        ('public.intenciones_reconocimientos', 'intenciones_reconocimientos_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '1b7e089f196e770f0c6e5eda43e936a05f19167ee56bd526e4aadd79510f22fd'),
        ('public.intenciones_reconocimientos', 'intenciones_reconocimientos_select_propietario_rpc', 'r', true, 'propietario_rpc', '1b7e089f196e770f0c6e5eda43e936a05f19167ee56bd526e4aadd79510f22fd', '-'),
        ('public.jornadas', 'jornadas_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', 'fcd4b9e5c506865d27802d0bb2b29e4641256b3ef3e7736cf70018a8b487753a'),
        ('public.jornadas', 'jornadas_select_authenticated', 'r', true, 'authenticated', '4ad6401e31b3fc5c6236d32cedbf838f32d2dc194a5e38751263589d6ee9a166', '-'),
        ('public.jornadas', 'jornadas_select_propietario_rpc', 'r', true, 'propietario_rpc', 'd6595bebd96310fae5338d181019cc5d5875af789ddb1451f6a6e25b8c6194f6', '-'),
        ('public.jornadas', 'jornadas_update_propietario_rpc', 'w', true, 'propietario_rpc', 'd6595bebd96310fae5338d181019cc5d5875af789ddb1451f6a6e25b8c6194f6', 'd6595bebd96310fae5338d181019cc5d5875af789ddb1451f6a6e25b8c6194f6'),
        ('public.movimientos_stock', 'movimientos_stock_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '8f391877a277a2ed530055f8d7cf680b558c3f3bcf84f5e8025def70b2b53d38'),
        ('public.movimientos_stock', 'movimientos_stock_select_empresa', 'r', true, 'authenticated', 'e8c101a0d54b67364efb6f17da8547f9d884acb7258a5a9aecbc9ecdeb2ae858', '-'),
        ('public.movimientos_stock', 'movimientos_stock_select_propietario_rpc', 'r', true, 'propietario_rpc', '68bbeffc27c510e59a8ab1a61a0b5fa64fea8bcecb92127d7dce7649e9a7716b', '-'),
        ('public.operaciones', 'operaciones_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '3bba9dfdb09db0eab7868dd4314d7e7fc08e6d78bf028ed030d80f5b02f7d270'),
        ('public.operaciones', 'operaciones_select_empresa', 'r', true, 'authenticated', 'd01b45289f98434f64fb930d3e02a3dc0c308f2d7e27ad9c83d982e11d917cd1', '-'),
        ('public.operaciones', 'operaciones_select_propietario_rpc', 'r', true, 'propietario_rpc', 'baf826151f26cdab9fad8b70acc053d6b19a4be4f9f7c032f69e4ddd34e3b7a5', '-'),
        ('public.perfiles', 'perfiles_select_empresa_lector', 'r', true, 'lector_perfiles_rpc', 'd61fddba9cfc8171907ddbdffe0f980a3889db16ce57ee2be1b17dc9921b3cef', '-'),
        ('public.perfiles', 'perfiles_select_propio_propietario_rpc', 'r', true, 'propietario_rpc', 'f9df022887a9bf40bb64e0268a166bbe85103570435da01731ef58c4e65e3c49', '-'),
        ('public.perfiles', 'perfiles_select_propio', 'r', true, 'authenticated', '39a1470a2578d10ef0d6d5631ed75a1d0185e6df95f2648b3eec5875e5e7dbb9', '-'),
        ('public.productos', 'productos_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', 'ce327c95a289293f4241c557ba844cb8e082741063d6858a3f02e1fd87363d67'),
        ('public.productos', 'productos_select_empresa', 'r', true, 'authenticated', '4b491451e3361d04719f5c09425b4f279a1990f400348cf7c48095cac8b6f674', '-'),
        ('public.productos', 'productos_select_propietario_rpc', 'r', true, 'propietario_rpc', 'a03261cf4a3eda6f91a59b1505967e454d58eb44e35ffad71b8f76d698289a2d', '-'),
        ('public.productos', 'productos_update_propietario_rpc', 'w', true, 'propietario_rpc', '0332c27d34c4aed473051ab61f768a4193f0545887e8a3e53d17e314e9a39056', '0332c27d34c4aed473051ab61f768a4193f0545887e8a3e53d17e314e9a39056'),
        ('public.reasignaciones_vendedor', 'reasignaciones_vendedor_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', 'a18f29f3614e1eb5ee4a0c3ebaf763f72a15d62c717fefcb267976cf9dbd42c3'),
        ('public.reasignaciones_vendedor', 'reasignaciones_vendedor_select_gestion', 'r', true, 'authenticated', 'dc0ca300f50b5fcc7dab37c357bdbd6a9a27f5a427d6def5db360ddd6f454e05', '-'),
        ('public.ubicaciones', 'ubicaciones_insert_propietario_rpc', 'a', true, 'propietario_rpc', '-', '1d95b98039b32e8e7aaebe66182802f72600291d0664ec8f5ca9319fe92e83f1'),
        ('public.ubicaciones', 'ubicaciones_select_empresa', 'r', true, 'authenticated', '69d2f8af31fb9ef9868117045d203ae987e731702eb47cc276d635e50d30a330', '-'),
        ('public.ubicaciones', 'ubicaciones_select_propietario_rpc', 'r', true, 'propietario_rpc', 'bb14c47bcdc4eac6b676fbd86574d84146f4d9f7584b3ebc14b865b2266257e8', '-')
      ) AS m(tabla, politica, cmd, permisiva, roles, h_using, h_check)
  LOOP
    v_politicas := v_politicas || (v_b.tabla || '|' || v_b.politica);

    v_oid_rel := pg_catalog.to_regclass(v_b.tabla);
    IF v_oid_rel IS NULL THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_TABLA_AUSENTE] falta la tabla % de la política %.', v_b.tabla, v_b.politica;
    END IF;
    IF v_oid_rel <> ALL (v_rels_manifiesto) THEN
      v_rels_manifiesto := v_rels_manifiesto || v_oid_rel;
    END IF;

    SELECT p.polcmd::pg_catalog.text,
           p.polpermissive,
           (SELECT pg_catalog.string_agg(CASE WHEN r.r = 0 THEN 'public'
                                              ELSE r.r::pg_catalog.regrole::pg_catalog.text END,
                                         ',' ORDER BY 1)
              FROM pg_catalog.unnest(p.polroles) AS r(r)),
           COALESCE(pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
             pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'UTF8')), 'hex'), '-'),
           COALESCE(pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
             pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), 'UTF8')), 'hex'), '-')
      INTO v_pol_cmd, v_pol_perm, v_pol_roles, v_pol_using, v_pol_check
      FROM pg_catalog.pg_policy p
     WHERE p.polrelid = v_oid_rel AND p.polname = v_b.politica;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_AUSENTE] falta la política % sobre % (oid %).', v_b.politica, v_b.tabla, v_oid_rel;
    END IF;
    IF v_pol_cmd IS DISTINCT FROM v_b.cmd THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_COMANDO] %.% tiene comando %, se esperaba %.', v_b.tabla, v_b.politica, v_pol_cmd, v_b.cmd;
    END IF;
    IF v_pol_perm IS DISTINCT FROM v_b.permisiva THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_MODO] %.% tiene PERMISSIVE = %, se esperaba %.', v_b.tabla, v_b.politica, v_pol_perm, v_b.permisiva;
    END IF;
    IF v_pol_roles IS DISTINCT FROM v_b.roles THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_ROLES] %.% tiene roles %, se esperaba %.', v_b.tabla, v_b.politica, COALESCE(v_pol_roles, 'ninguno'), v_b.roles;
    END IF;
    IF v_pol_using IS DISTINCT FROM v_b.h_using THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_USING] %.% tiene una expresión USING distinta de la aprobada (sha256 %, esperado %).', v_b.tabla, v_b.politica, v_pol_using, v_b.h_using;
    END IF;
    IF v_pol_check IS DISTINCT FROM v_b.h_check THEN
      RAISE EXCEPTION 'validar_topologia: [POLITICA_CHECK] %.% tiene una expresión WITH CHECK distinta de la aprobada (sha256 %, esperado %).', v_b.tabla, v_b.politica, v_pol_check, v_b.h_check;
    END IF;
  END LOOP;

  IF pg_catalog.cardinality(v_politicas) IS DISTINCT FROM 38 THEN
    RAISE EXCEPTION 'validar_topologia: [POLITICA_MANIFIESTO] el manifiesto debe tener 38 políticas, tiene %.', pg_catalog.cardinality(v_politicas);
  END IF;

  --     Las 13 relaciones del manifiesto (las 13 tablas del inventario de T3P-05).
  IF pg_catalog.cardinality(v_rels_manifiesto) IS DISTINCT FROM 13 THEN
    RAISE EXCEPTION 'validar_topologia: [POLITICA_MANIFIESTO] el manifiesto debe cubrir 13 relaciones, cubre %.', pg_catalog.cardinality(v_rels_manifiesto);
  END IF;

  --     Políticas adicionales (B11-02): sobre una relación manifestada, toda
  --     política fuera del manifiesto (permisiva o restrictiva) se rechaza.
  SELECT pg_catalog.string_agg(n.nspname::pg_catalog.text || '.' || c.relname::pg_catalog.text
                               || '|' || p.polname::pg_catalog.text, ', ' ORDER BY 1)
    INTO v_txt
    FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
   WHERE p.polrelid = ANY (v_rels_manifiesto)
     AND (n.nspname::pg_catalog.text || '.' || c.relname::pg_catalog.text
          || '|' || p.polname::pg_catalog.text) <> ALL (v_politicas);
  IF v_txt IS NOT NULL THEN
    RAISE EXCEPTION 'validar_topologia: [POLITICA_ADICIONAL] políticas no autorizadas sobre relaciones manifestadas: %.', v_txt;
  END IF;

  --     Políticas sobre relaciones de public o privado fuera del manifiesto: no
  --     hay contrato aprobado contra el cual compararlas. No se rechazan por
  --     inventario ni se declaran verificadas; se informan como pendientes.
  SELECT pg_catalog.string_agg(n.nspname::pg_catalog.text || '.' || c.relname::pg_catalog.text
                               || '|' || p.polname::pg_catalog.text
                               || '|' || CASE WHEN p.polpermissive THEN 'permisiva' ELSE 'restrictiva' END,
                               ', ' ORDER BY 1)
    INTO v_txt2
    FROM pg_catalog.pg_policy p
    JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relnamespace IN (v_oid_publico, v_oid_privado)
     AND p.polrelid <> ALL (v_rels_manifiesto);
  IF v_txt2 IS NOT NULL THEN
    RAISE WARNING 'validar_topologia: [PENDIENTE_DECISION_POLITICA] políticas NO VERIFICADAS sobre relaciones fuera del manifiesto (sin contrato aprobado): %.', v_txt2;
  END IF;

  PERFORM pg_catalog.set_config('search_path', v_search_path_previo, true);

  RAISE NOTICE 'validar_topologia: [T3P-06] manifiesto exacto de 38 políticas RLS conforme y sin políticas adicionales sobre las 13 relaciones manifestadas; las políticas de otras relaciones no se verifican (sin contrato aprobado).';

  -- ======================================================
  -- 6. Resumen: topología válida
  -- ======================================================

  --     B11-04: las violaciones ya abortaron con EXCEPTION (estado C). Aquí se
  --     distingue A (sin superficies pendientes) de B (con relaciones, owners o
  --     políticas sin contrato auditado). Las políticas fuera del manifiesto se
  --     recuentan aquí, sin modificar la sección 5.
  IF EXISTS (SELECT 1
               FROM pg_catalog.pg_policy p
               JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
              WHERE c.relnamespace IN (v_oid_publico, v_oid_privado)
                AND p.polrelid <> ALL (v_rels_manifiesto)) THEN
    v_pendientes := v_pendientes + 1;
  END IF;

  RAISE NOTICE 'Roles técnicos, membresías (O-3/D-2), ownership y privilegios efectivos de las relaciones inventariadas: conformes (T3P-07).';
  RAISE NOTICE 'RLS obligatoria sin FORCE en las 13 tablas expuestas (owner postgres) y en las tablas adicionales de public (owner no validado); ninguna vista adicional accesible elude la RLS según sus dependencias (T3P-05, P4, B11-03).';
  RAISE NOTICE 'Funciones: 46 firmas exactas con contrato completo, auxiliares conformes e inventario SECURITY DEFINER exhaustivo en public, privado y graphql_public (Bloque A, ADR-001 §17.3).';
  RAISE NOTICE 'service_role: denegado por defecto, excepción SELECT sobre public.productos (T3P-08, P11).';
  RAISE NOTICE 'Políticas RLS: manifiesto exacto de 38 políticas sobre 13 relaciones; políticas de otras relaciones no verificadas (T3P-06).';
  RAISE NOTICE '---';
  IF v_modo_local THEN
    RAISE WARNING '=== validar_topologia: [ESTADO_LOCAL_SIN_O4] invariantes restantes verificados con O-4 ausente por marcador de laboratorio local (% grupo(s) pendiente(s)). NO es ESTADO_A ni conformidad de topología. ===', v_pendientes;
  ELSIF v_pendientes = 0 THEN
    RAISE NOTICE '=== validar_topologia: [ESTADO_A] invariantes exigidos por este preflight verificados; ninguna superficie pendiente detectada. Esto no equivale a una verificación completa de seguridad. ===';
  ELSE
    RAISE WARNING '=== validar_topologia: [ESTADO_B] invariantes exigidos por este preflight verificados, pero hay % grupo(s) de relaciones, owners o políticas sin contrato auditado (ver PENDIENTE_DECISION_*). Topología NO declarada conforme. ===', v_pendientes;
  END IF;

END$$;
