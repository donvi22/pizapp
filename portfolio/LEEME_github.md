# Publicar Pizapp en GitHub

## 1. Preparar los archivos

Extrae el ZIP en `C:\Users\Donvi\Desktop\Python\PizarraApp`. El paquete añade documentación y el workflow; no modifica el código de las pantallas ni de la API. Si ya tenías un README o un workflow con el mismo nombre, conserva una copia antes de reemplazarlos.

Desde PowerShell:

```powershell
cd C:\Users\Donvi\Desktop\Python\PizarraApp
powershell -ExecutionPolicy Bypass -File .\portfolio\preparar_portfolio.ps1
```

El script conserva el contenido de tu `.gitignore` y añade reglas que falten. Añade capturas reales según `docs/capturas/README.md` y vuelve a ejecutarlo.

## 2. Crear el repositorio

En GitHub crea un repositorio público llamado `pizapp`. Déjalo vacío: sin generar README, `.gitignore` ni licencia. Esos archivos se gestionan desde la carpeta local; la elección de licencia puede hacerse después.

Descripción sugerida: «Aplicación colaborativa de proyectos con pizarra, tareas y permisos. API Django REST Framework y cliente Flutter.»

En el apartado About añade la URL `https://donvi22.pythonanywhere.com/`. Temas sugeridos: `python`, `django`, `django-rest-framework`, `flutter`, `dart`, `portfolio`.

Copia la URL HTTPS del repositorio. El usuario de GitHub no tiene por qué coincidir con el de PythonAnywhere.

## 3. Comprobar si existe un repositorio local

Desde la raíz de PizarraApp:

```powershell
git rev-parse --show-toplevel
git remote -v
```

Si indica que no hay repositorio, puedes seguir con la instalación nueva del siguiente apartado. Si muestra otra carpeta como raíz o ya hay un remoto, revisa esa situación antes de inicializar o cambiar remotos. No sobrescribas un remoto de otro proyecto.

## 4. Primera publicación de una carpeta sin Git

Sustituye `URL_HTTPS_DEL_REPOSITORIO` por la URL copiada; no ejecutes el marcador literalmente.

```powershell
git init -b main
git add .
git status --short
git diff --cached --stat
```

Antes del commit comprueba que figuran `App/pubspec.yaml`, `App/pubspec.lock`, `App/lib/`, el backend con sus migraciones, el README y `.github/workflows/ci.yml`. No deben figurar `.venv`, bases de datos, `backend/media`, archivos `.env` o `.production.json`, ni paquetes de `deploy/output`.

Si tu `.gitignore` anterior contiene reglas que excluyen código o el lockfile, corrígelas. Las reglas añadidas no borran las existentes. Si algún archivo privado ya estaba versionado en un repositorio existente, añadirlo a `.gitignore` no lo retira del historial: revisa ese caso antes de publicar.

Una vez revisado lo que se va a subir:

```powershell
git commit -m "Presenta Pizapp con demo, documentacion y CI"
git remote add origin URL_HTTPS_DEL_REPOSITORIO
git push -u origin main
```

Si Git pide configurar tu nombre o correo, utiliza los datos de tu cuenta; puedes usar el correo privado de GitHub. Si aparece cualquier error de remoto, permisos o ramas, conserva el mensaje y revísalo antes de continuar. No utilices un push forzado.

## 5. Validación final

Abre el repositorio y comprueba que:

- El README y las capturas se ven correctamente.
- El enlace de demo abre la aplicación.
- Las carpetas App y backend contienen el código, y no datos privados.
- En Actions, el workflow **Comprobaciones de Pizapp** termina con sus dos trabajos en verde.

El workflow está preparado; su ejecución en GitHub solo queda validada después de ese primer push. Si falla, abre el paso que falló y conserva su salida para corregir el problema concreto.

Hasta que estén publicadas las capturas, el repositorio y las comprobaciones, el bloque de portfolio sigue en curso.
