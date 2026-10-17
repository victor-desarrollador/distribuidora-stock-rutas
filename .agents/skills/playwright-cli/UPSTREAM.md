# Upstream

Herramienta:
Microsoft Playwright CLI

Repositorio:
https://github.com/microsoft/playwright-cli

CLI instalado y usado para generar este skill:
0.1.22

Instalación utilizada:
playwright-cli install --skills

Uso en este proyecto:
- validación funcional en navegador;
- pruebas responsive desktop/móvil;
- inspección de consola y requests;
- screenshots/traces cuando correspondan;
- apoyo para generar y depurar pruebas E2E.

Notas:
- `.playwright-cli/` es estado local y está ignorado por Git.
- El skill no reemplaza los tests automatizados del repositorio.
- Los flujos críticos deben tener tests reproducibles; una sesión manual de navegador no constituye por sí sola evidencia suficiente.

Commit upstream auditado:
b85c7a736bb473bf55b584e54a09ffa698d6d871
