# Activar correos de BARBER PRO

El ZIP contiene el sitio estático y el backend de notificaciones. No necesitas cambiar el diseño ni instalar un servidor web. El modo demo no envía correos. La cola se procesa cada minuto y los fallos temporales se reintentan hasta cinco veces. Se envían confirmación, cancelación, recordatorio 24 horas antes (solo para reservas hechas con más de 24 horas de antelación) y aviso a la barbería si se configura su destinatario.

## 1. Supabase
- Si es un proyecto nuevo, ejecuta `supabase.sql` y sigue el README para crear el administrador y configurar `config.js`. Si ya tienes un proyecto, conserva tu `config.js` real y NO repitas `supabase.sql`.
- En SQL Editor ejecuta `notifications.sql`. No elimina citas ni clientes existentes. No genera mensajes retroactivos.

## 2. Resend
- Crea una cuenta en https://resend.com y genera una API key de envío.
- Verifica un dominio en Domains y elige un remitente, por ejemplo `BARBER PRO <citas@tudominio.com>`. Para una prueba limitada puedes utilizar `onboarding@resend.dev`; Resend solo permite enviar a la dirección de tu propia cuenta en ese modo.

## 3. Edge Function
En Supabase > Edge Functions crea/despliega una función llamada `send-booking-email` con el contenido de `supabase/functions/send-booking-email/index.ts`. Desactiva la verificación JWT del gateway para esta función: el código exige un secreto independiente en la cabecera `x-booking-secret`. Alternativamente, con CLI instalada y autenticada, desde esta carpeta ejecuta `supabase link --project-ref TU_REF` y `supabase functions deploy send-booking-email --no-verify-jwt`.

En Edge Functions > Secrets añade:
- `RESEND_API_KEY`: clave de Resend.
- `BOOKING_FROM_EMAIL`: remitente verificado.
- `BOOKING_ADMIN_EMAIL`: correo de la barbería (opcional; si no existe se omite su aviso).
- `BOOKING_CRON_SECRET`: cadena aleatoria larga, de al menos 32 caracteres, exclusiva de esta integración. Puedes generarla localmente con `openssl rand -hex 32`.

Las variables SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las proporciona Supabase. Nunca pongas ninguna clave privada en GitHub ni en config.js.

## 4. Activar el programador
En Supabase Vault crea dos secretos:
- `barber_project_url`: URL del proyecto, por ejemplo `https://TU_REF.supabase.co`.
- `barber_cron_secret`: exactamente el mismo valor de BOOKING_CRON_SECRET.
En SQL Editor ejecuta `activate-cron.sql`. Consulta la guía oficial si necesitas ubicar las opciones: https://supabase.com/docs/guides/functions/schedule-functions.

## 5. Publicar y probar
Sube los archivos web `index.html`, `app.js`, `styles.css` y tu `config.js` configurado al repositorio de GitHub Pages. Puedes guardar también los archivos SQL y la función, que no contienen secretos. Reserva una cita con tu correo de prueba y consulta SQL Editor:

```sql
select appointment_id,kind,state,attempts,due_at,sent_at,last_error
from public.booking_email_queue order by created_at desc limit 20;
```

`sent` indica que Resend aceptó el mensaje, no que el destinatario lo haya leído o que haya llegado a su bandeja. `pending` está en cola; `skipped` fue omitido; `failed` requiere revisar la configuración. Consulta también los logs de Edge Functions y Resend. Para reintentar una fila fallida tras corregir un error:

```sql
update public.booking_email_queue set state='pending',attempts=0,due_at=now(),last_error=null where id='UUID_DE_LA_FILA' and state='failed';
```

No reintentes manualmente mensajes que Resend ya aceptó: su ventana de deduplicación es limitada. Para pruebas de cancelación, cancela una cita desde el panel y verifica que llegue el correo correspondiente. El recordatorio utiliza hora de Colombia. Si modificas la fecha de una cita directamente en la base de datos, la cola no se reprograma; esta versión no incluye reprogramación de citas.

## Seguridad y alcance
La cola es privada, no accesible al público. La API de Resend solo se usa en el servidor. El formulario público original sigue requiriendo protección antispam/CAPTCHA y límites de tráfico antes de operar comercialmente: de lo contrario un tercero podría generar reservas y correos no deseados. No hay pruebas de entrega reales hasta configurar las cuentas. No publiques información personal ni claves en el repositorio.
