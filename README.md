# TCG Seller

Aplicación Android para administrar subastas publicadas por una página de Facebook, sus pujas, clientes, pedidos y conversaciones de Messenger.

## Proyecto conectado

- Android application ID: `com.jyuls.tcgseller`
- Supabase project: `jmoacqfkefpcwxjfvrqc`
- Supabase URL: `https://jmoacqfkefpcwxjfvrqc.supabase.co`
- Meta App ID: `2565886913849368`
- Zona horaria del negocio: `America/Tijuana`

La clave publicable de Supabase puede vivir en Flutter. `META_APP_SECRET`, tokens de Facebook, claves de servicio y claves de cifrado nunca deben agregarse al repositorio.

## Configuración pendiente en Supabase

En **Authentication → Sign In / Providers → Facebook**:

1. Activa Facebook.
2. Configura App ID `2565886913849368`.
3. Pega el App Secret directamente en el Dashboard.

En **Edge Functions → Secrets** crea:

- `META_APP_ID=2565886913849368`
- `META_APP_SECRET` con el secreto de Meta.
- `META_WEBHOOK_VERIFY_TOKEN` con un valor aleatorio que también configurarás en Meta.
- `TOKEN_ENCRYPTION_KEY` con 32 bytes aleatorios codificados en Base64.
- `META_GRAPH_VERSION=v25.0` opcional; permite fijar una versión distinta aprobada por Meta.

Puedes generar los dos valores aleatorios localmente con PowerShell sin publicarlos:

```powershell
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToBase64String($bytes)
[guid]::NewGuid().ToString('N')
```

## Configuración pendiente en Meta

- OAuth redirect permitido: `https://jmoacqfkefpcwxjfvrqc.supabase.co/auth/v1/callback`
- Webhook callback: `https://jmoacqfkefpcwxjfvrqc.supabase.co/functions/v1/meta-webhook`
- Verify token: el mismo valor de `META_WEBHOOK_VERIFY_TOKEN`.
- Suscribir la página a `feed`, `messages`, `messaging_postbacks`, `message_deliveries` y `message_reads`, según los permisos aprobados.
- Mantener la app en Development durante las pruebas con el usuario administrador y la página creada.

El login solicita permisos de páginas, publicaciones, interacción y Messenger. Meta puede exigir revisión y verificación empresarial antes de conceder acceso avanzado en modo Live.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Las migraciones están en `supabase/migrations` y las Edge Functions en `supabase/functions`. El trabajador se ejecuta cada minuto. Para cerrar una subasta espera 60 segundos para reconciliar comentarios, pero sólo acepta una puja cuando `meta_created_at < ends_at`; una puja exactamente a la hora del cierre es inválida.
