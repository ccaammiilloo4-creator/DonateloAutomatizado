# BARBER PRO — software web de barbería

Aplicación responsive lista para **GitHub Pages**, con reservas públicas de citas y panel de administración. No necesita Node.js ni compilación: es HTML/CSS/JavaScript.

## Funcionalidades

- Portal de reserva para clientes (sin crear cuenta).
- Selección de servicio, barbero, fecha y horarios disponibles.
- Prevención de cruces de citas en la base de datos, incluso cuando dos clientes reservan a la vez.
- Panel privado con métricas, agenda, estados de citas, directorio de clientes, servicios, profesionales y ajustes.
- Horarios de trabajo por profesional, duración y precio por servicio.
- Diseño adaptable a celulares.
- Demostración local, sin configuración, usando `localStorage` (solo el navegador actual).
- Producción con Supabase: datos compartidos entre celulares, computadores y visitantes.

## 1. Probar de inmediato

Abre `index.html` en tu navegador. En **modo demo**, cualquier correo y contraseña abren el panel. Los datos solo se guardan en ese navegador; **no es seguridad ni una base de datos en línea**. Puedes subir los archivos y mostrar la demo pública, pero NO tomar reservas reales hasta conectar Supabase.

## 2. Crear la base de datos real en Supabase (gratis para empezar)

1. Crea un proyecto en <https://supabase.com/>.
2. Ve a **SQL Editor** y ejecuta completo el archivo `supabase.sql`.
3. En **Authentication > Users**, pulsa **Add user > Create new user**; escribe el correo y contraseña privada de tu administrador. Es recomendable marcar el email como confirmado.
4. Ve a **SQL Editor** y ejecuta este SQL, reemplazando el correo por el usuario real:

   ```sql
   insert into public.admin_users(user_id)
   select id from auth.users where email='admin@tubarberia.com'
   on conflict do nothing;
   ```

   Solo los usuarios agregados en `admin_users` pueden ver/modificar información privada.
5. En **Project Settings > API** (o **Connect > API keys** según la interfaz), copia la **Project URL** y la clave **anon/public/publishable**. **No uses nunca service_role ni secret key**.
6. Abre `config.js` y coloca los valores:

   ```js
   window.BARBER_CONFIG = {
     supabaseUrl: 'https://TU-PROYECTO.supabase.co',
     supabaseAnonKey: 'TU_CLAVE_PUBLICA_ANON'
   };
   ```
7. Publica en GitHub Pages y abre el sitio. Entra a **Administración** con tu usuario creado; personaliza nombres, precios, barberos, jornada y contacto.

Nota: Para producción, configura en Supabase > Authentication > URL Configuration el **Site URL** con la dirección pública del proyecto. El acceso del administrador usa correo + contraseña.

## 3. Publicar en GitHub Pages

1. Crea un repositorio nuevo en <https://github.com/new>, por ejemplo `mi-barberia`.
2. En el repositorio, pulsa **Add file > Upload files**.
3. Arrastra **todos los archivos de esta carpeta** (`index.html`, `styles.css`, `app.js`, `config.js`, `supabase.sql` y `README.md`), no el ZIP, y confirma con **Commit changes**.
4. Ve a **Settings > Pages**.
5. En **Build and deployment**, selecciona **Deploy from a branch**; rama **main**, carpeta **/(root)**; guarda.
6. Tu enlace será similar a `https://TU-USUARIO.github.io/mi-barberia/`.

También puedes usar Git desde una terminal dentro de la carpeta:

```bash
git init
git add .
git commit -m "Lanzamiento BARBER PRO"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/mi-barberia.git
git push -u origin main
```

## 4. Operación y límites importantes

- GitHub Pages **solo aloja archivos estáticos**. No guarda ni sincroniza citas. Para recibir reservas reales es imprescindible conectar Supabase u otro backend.
- En modo demo, la contraseña **no protege** el panel; es únicamente una maqueta funcional local.
- En producción, la seguridad se basa en autenticación y políticas RLS de Supabase; las claves publicables sí pueden estar en el navegador. Las claves secretas jamás.
- Para una actividad comercial conviene habilitar protección antispam/CAPTCHA y límites de tráfico en reservas públicas, backups periódicos, consentimiento y política de tratamiento de datos conforme a la normatividad aplicable. Esta primera versión no incluye pagos, notificaciones automáticas de WhatsApp, cancelación por parte del cliente ni múltiples sucursales.
- Esta versión trabaja con horarios locales de **Colombia (America/Bogota)**. El navegador que muestra las citas debería estar en esa zona horaria. Se generan turnos cada 15/30/60 minutos según configuración; la base de datos valida las reservas.
- El cliente recibe confirmación en pantalla y, cuando se activa la integración, por correo. No incluye SMS. Consulta `CORREOS.md` para instalar las notificaciones.
- La función SQL de reservas se expone públicamente; en un entorno abierto considera un CAPTCHA a través de un backend/Edge Function para impedir spam automatizado.

## Notificaciones por correo

Sigue la guía `CORREOS.md` para instalar la migración, desplegar la función y activar el programador. No vuelvas a ejecutar `supabase.sql` en una base existente.

## Archivos

- `index.html`: interfaces públicas y privadas.
- `styles.css`: aspecto visual.
- `app.js`: lógica de reservas y administración.
- `config.js`: configuración pública para conectar Supabase.
- `supabase.sql`: tablas, políticas RLS y funciones para reservas.
- `README.md`: instrucciones.
