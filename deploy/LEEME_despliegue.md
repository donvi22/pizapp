# Pizapp: preparación del despliegue (bloque 4 de 5)

Estado: código preparado y backend comprobado. Aún falta compilar Flutter en tu equipo, configurar tu cuenta de alojamiento y verificar la dirección pública.

## 1. Copiar y comprobar en Windows

Extrae el ZIP en `C:\Users\Donvi\Desktop\Python\PizarraApp`, conservando las carpetas `App`, `backend` y `deploy`. Los archivos incluidos están completos.

En backend, con el entorno virtual activado:

```powershell
python manage.py check
python manage.py test accounts projects config
```

En App:

```powershell
flutter analyze
```

No hacen falta nuevas migraciones ni dependencias para las pruebas locales.

## 2. Crear la cuenta gratuita

Abre https://www.pythonanywhere.com/pricing/ y elige Beginner ($0). El proveedor anuncia una web, 512 MiB de disco y caducidad de la web de un mes. Revisa su fecha de caducidad en el panel Web para mantener disponible la demo.

Conserva tu usuario y el dominio asignado. Si eliges el sistema europeo, utiliza el dominio exacto que te indique el panel.

## 3. Preparar el paquete que se subirá

Desde la raíz de PizarraApp:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\preparar_demo.ps1
```

El cambio de ExecutionPolicy afecta solo a ese proceso. El script pasa flutter analyze, compila Flutter para `/app/` y crea `deploy/output/pizapp_demo_FECHA_HORA.zip`. Conserva el nombre mostrado al terminar.

El paquete contiene backend y web compilada. No incluye tu entorno virtual, base de datos local, media, cachés ni el archivo privado .production.json. Las cuentas de la demo se registrarán desde la app publicada.

La API se selecciona automáticamente: servidor local en HTTP durante tus pruebas actuales y el mismo origen de la web al acceder mediante HTTPS. Para una app nativa puede indicarse `--dart-define=API_BASE_URL=https://DOMINIO/api`.

## 4. Subir y configurar PythonAnywhere

Estos pasos se harán cuando conozcamos tu usuario y dominio. Sustituye los marcadores; no son comandos para Windows.

En Files, sube el paquete a tu directorio personal. Abre una consola Bash:

```bash
mkdir -p ~/PizarraApp
unzip ~/pizapp_demo_FECHA_HORA.zip -d ~/PizarraApp
python3.13 -m venv ~/.virtualenvs/pizapp
source ~/.virtualenvs/pizapp/bin/activate
cd ~/PizarraApp/backend
python -m pip install --no-cache-dir -r requirements-production.txt
python prepare_production.py --hostname TU_DOMINIO
export DJANGO_SETTINGS_MODULE=config.settings_production
python manage.py migrate
python manage.py collectstatic --noinput
python manage.py check --deploy
```

Selecciona la misma versión de Python al crear el entorno y al configurar la web. La imagen innit ofrece Python 3.13; si tu panel ofrece 3.12, usa 3.12 en ambos sitios.

prepare_production.py genera una clave en el servidor y se niega a sustituir una configuración ya existente. No compartas ni subas a GitHub el archivo .production.json.

En Web, crea una aplicación con Manual configuration (no la opción Django para proyectos nuevos). Indica:

- Source code y Working directory: `/home/TU_USUARIO/PizarraApp/backend`
- Virtualenv: `/home/TU_USUARIO/.virtualenvs/pizapp`

Edita el archivo WSGI enlazado desde el panel Web y pega el contenido de `deploy/pythonanywhere_wsgi.py`, reemplazando TU_USUARIO. Ese archivo del panel es distinto de backend/config/wsgi.py.

En Static files añade:

| URL | Directorio |
| --- | --- |
| `/static/` | `/home/TU_USUARIO/PizarraApp/backend/staticfiles` |
| `/app/` | `/home/TU_USUARIO/PizarraApp/backend/webapp` |

Los adjuntos se descargan mediante la API autenticada. No añadas un mapeo estático para media ni para todo backend.

Activa Force HTTPS en Web y pulsa Reload.

## 5. Verificar el enlace público

Primero abre `https://TU_DOMINIO/api/health/`: debe mostrar `{"status":"ok"}`. Después abre `https://TU_DOMINIO/`: debe redirigir a `/app/index.html`.

Registra dos cuentas de prueba, crea un proyecto, comparte la invitación, edita una tarea, sube y descarga un archivo pequeño y recarga el navegador. Comprueba que un usuario ajeno no accede al proyecto. Repite la prueba desde el móvil con el ordenador apagado.

La demo tiene límites de 20 MiB por archivo, 100 MiB por proyecto y 200 MiB de adjuntos en total. El disco del plan también contiene dependencias, base de datos y la web compilada; vigila el uso en Files. La base de datos SQLite y media permanecen en el directorio del servidor al recargar la web.

Al actualizar, sustituye únicamente los archivos del nuevo paquete, ejecuta las nuevas migraciones si las hay y recarga Web. Conserva la base de datos, media y .production.json. Descarga una copia de la base de datos y media antes de cambios importantes.

## Notas de configuración

DEBUG está desactivado en settings_production.py y los dominios se limitan al configurado. Se fuerza HTTPS y las cookies son seguras. El frontend y la API comparten dominio, por lo que no se abren orígenes CORS adicionales.

check --deploy informa de 3 comprobaciones silenciadas deliberadamente: recomendaciones de HSTS para subdominios/preload y ausencia de un remitente de correo. Esta primera demo aplica HSTS durante una hora a su propio dominio, no registra el dominio del proveedor en preload y utiliza avisos dentro de la app; no envía emails.

Antes de publicar el código en GitHub, añade las líneas de deploy/gitignore_fragment.txt a tu .gitignore.

## Fuentes consultadas

- https://www.pythonanywhere.com/pricing/
- https://help.pythonanywhere.com/pages/FreeAccountsFeatures
- https://help.pythonanywhere.com/pages/DeployExistingDjangoProject/
- https://help.pythonanywhere.com/pages/StaticFiles/
- https://help.pythonanywhere.com/pages/ForcingHTTPS/
- https://help.pythonanywhere.com/pages/PythonVersions/
- https://docs.djangoproject.com/en/6.0/howto/deployment/checklist/
- https://docs.flutter.dev/deployment/web
