const updatedAt = '23 de junio de 2026'
const contactEmail = 'elegido1999@hotmail.com'
const appName = 'TCG Seller'

const pages: Record<string, { title: string; body: string }> = {
  privacy: {
    title: `Política de privacidad de ${appName}`,
    body: `
${appName} es una aplicación de uso personal para administrar publicaciones, subastas, clientes, pedidos y mensajes de una página de Facebook conectada por su administrador.

Datos que se recopilan
- Información básica de la cuenta de Facebook usada para iniciar sesión.
- Lista de páginas de Facebook administradas por el usuario.
- Datos de la página conectada, publicaciones, fotografías, comentarios y pujas relacionados con las subastas.
- Datos operativos creados dentro de la app, como clientes, pedidos, notas, lugares de entrega y estados de pago o entrega.
- Mensajes recibidos o enviados desde la página cuando el permiso de Messenger esté habilitado y permitido por Meta.

Uso de los datos
Los datos se usan únicamente para operar la aplicación: publicar subastas, leer comentarios, identificar pujas, generar pedidos, administrar clientes y comunicarse con personas que interactúan con la página conectada.

Almacenamiento y terceros
Los datos se almacenan en Supabase y se procesan con servicios de Meta/Facebook únicamente para las funciones autorizadas por el usuario. Los datos no se venden ni se comparten con terceros para publicidad externa.

Conservación y eliminación
Los datos se conservan mientras la app sea usada para administrar la página. El usuario puede solicitar la eliminación de datos escribiendo a ${contactEmail}.

Contacto
Para dudas sobre privacidad o datos personales, escribe a ${contactEmail}.
`,
  },
  'data-deletion': {
    title: `Eliminación de datos de ${appName}`,
    body: `
Si deseas eliminar los datos asociados a ${appName}, envía una solicitud a ${contactEmail}.

Qué incluir en la solicitud
- Nombre de la página de Facebook conectada.
- Correo o perfil usado para administrar la página.
- Una descripción breve indicando que deseas eliminar los datos de ${appName}.

Qué se elimina
Se eliminarán o anonimizarán credenciales de Meta, datos de conexión, páginas conectadas, publicaciones, fotografías almacenadas, comentarios procesados, clientes, pedidos, mensajes y configuraciones relacionadas con la cuenta solicitante, salvo datos que deban conservarse por motivos legales o de seguridad.

Tiempo de respuesta
La solicitud será revisada y procesada en un plazo razonable. Se enviará confirmación al correo desde el que se realizó la solicitud.
`,
  },
  terms: {
    title: `Términos de uso de ${appName}`,
    body: `
${appName} es una herramienta de uso personal para administrar una página de Facebook, subastas, clientes, pedidos y comunicación relacionada.

Uso permitido
La aplicación debe usarse conforme a las políticas de Meta/Facebook, leyes aplicables y permisos concedidos por el usuario administrador de la página.

Responsabilidad
El usuario es responsable del contenido publicado, la gestión de pedidos, la atención a clientes y el cumplimiento de reglas comerciales o fiscales aplicables.

Contacto
Para soporte o dudas, escribe a ${contactEmail}.
`,
  },
}

function render(title: string, body: string) {
  return `${title}

${body.trim()}

Última actualización: ${updatedAt}
`
}

Deno.serve((req) => {
  const url = new URL(req.url)
  const key = url.pathname.split('/').filter(Boolean).at(-1) ?? 'privacy'
  const page = pages[key] ?? pages.privacy

  return new Response(render(page.title, page.body), {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  })
})
