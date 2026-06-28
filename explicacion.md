Esta aplicacion la hago principalmente para automatizar lo que hago manualmente con la gestion de las subastas asi que explicare a detalle mis procesos manuales para que despues explicar mi idea para automatizar.

Primero debo elegir lo que voy a subastar, usualmente piendo en que cada publicacion subasta debe irse en $100 pesos, por eso publico 20 fotos, osea 20 articulos, que inician con puja de $5 pesos, porque asi si se van en el minimo todas las subastas, pues juntaria los $100 pesos minimos, ya lo demas seria extra. Aveces pueden ser mas o menos imagenes.

Tomo fotos de la subastas, les escribo en las imagenes "SUBASTA" Y "5 PESO", cada unas de las 20 imagenes les pongo esos textos.

Despues creo una publicacion de facebook, le pongo un texto el cual nomas le cambio INICIO, TERMINA.

"SUBASTA DE $5 PESO
INICIA
25 de Junio
TERMINA
26 de Junio a las 9:00 PM
Puja mínima $5 Peso
Se puja por foto
Los ganadores serán notificados por inbox
En caso de no concretar se puede depositar para apartar la subasta para la próxima semana
Entregas:
Mundo Divertido
Domingo 10:00 AM - 11:00 AM
Game Hunters
Martes a Domingo
1:00 PM - 6:00 PM"

Una vez publicada la dejo asi hasta el dia siguiente, ahi como por las 5:00pm reviso la subasta y veo la puja mas alta y les doy un recordatorio de que la subasta termina a las 9:00pm y que la puja mas alta es ${cantidad}.

Cuando dan las 9:00pm exactas, termina la subasta, entonces empiezo a contactar a los ganadores, copio la foto y se la mando a la persona que gano diciendole "Ganaste con ${cantidad}". Y asi voy con cada personas, aveces a la misma persona le mando 4 fotos y con el mismo mensaje pero cambiando cantidad. Cuando termino de escribirle a los ganadores por messenger, solamente espero a que me manden un mensaje de confirmado.

Cuando llega el sabado agarro una cajita de ETB y varios separadores, lo que hago ahi es que abro el chat de un cliente veo todas las fotos que gano, las pongo en la etb, sumo los precios de las subastas y le digo que lo veo mañana en Mundo Divertido y que la cantidad total es ${cantidad}. Despues pongo un separador, voy al siguiente cliente y repito esta practica.

El domingo en MD cuando llego le tomo foto al puesto Tokyo Morningstore, hago un mensaje general en donde digo como voy vestido, digo que estare ahi hasta las 11:00pm

Lo que pienso que se puede automatizar:
Actualmente con esta app mi teoria es que el flujo pueda ser asi:

Primero elijo lo que voy a subastas, con la aplicacion pongo los parametros de fecha de inicio y finalizacion que normalmente edito manualente, tambien tomo las fotos, a las cuales ya se les pone automaticamente el texto y se publica en mi pagina de facebook. Ahi practicamente ya automatice toda la publicacion de facebook.

Ahora en la gestion de la subasta al dia siguiente a las 5:00pm se ejecuta la instruccion de recordar la subasta la cual tiene actualmente los siguientes textos:
"Recordatorio: esta subasta termina a las 9:00 p.m.. Puja actual: $20."
"Recordatorio: esta subasta termina a las 9:00 p.m.. Aún sin pujas."

Esto esta muy bien pero quisiera cambiarlos a:
"Esta subasta termina a las 9:00pm. Puja mas alta: $20."
"Esta subasta termina a las 9:00pm. Aún sin pujas."

Suenan mas organicos de esta forma.

Finalmente a las 9:00pm, se toma la publicacion y en cada foto se busca la puja mas alta, al encontrarla se le responde a ese comentario con el mensaje de "Ganaste esta subasta. Enviame mensaje para confirmar tu pedido."

Con esto ya la persona nos debe enviar mensaje para confirmar, ya si nos envia mensaje quiere decir que si nos confirma el pedido.

Cuando nos envie el mensaje, desde la app podremos registar que ese usuario gano la subasta o subastas, porque puede ganar multiples subastas. Despues de hacer el pedido se le envia mensaje de confirmacion. este mensaje tendra todas las imagenes de las subastas que gano y un texto, que es el siguiente:
"Pedido confirmado: ${cantidad total}. Para entregar en Mundo Divertido en el puesto Tokyo Morningstore."

El dia sabado es el dia donde normalmente debemos recordarle al cliente que tiene un pedido pendiente por recoger, asi que todos los clientes se les debe enviar un mensaje para recordarle que el dia de mañana, osea domingo, los veremos en mundo divertido en el puesto Tokyo Morningstore.

Ademas este dia es cuando agarro la ETB y hago los pedidos, en este caso el orden de los pedidos sera el orden que los ponga en la ETB.

El dia domingo lo que se hara es que cuando yo llegue a MD podre tomarle foto al puesto Tokyo Morningstore, y con un template de mensaje pondra lo fijo que es que estare hasta tal hora y me dejara nomas editar como voy vestido, ese mensaje una vez armado se le debe mandar a cada uno de los clientes, para que sepan donde estoy y como voy vestido.

CONSIDERACIONES

Comentarios de subastas:
Algunas personas comentan de muchas formas, por ejemplo
5
$5
5 peso
$5 pesos

En ese caso concreto todas dan a entender la misma cantidad pero esta de diferentes formas, la idea es ser flexibles y que las variantes similares a estas que se puse sean validas, en este caos la respuesta es que la puja seria de 5 pesos.

INICIO:
En este apartado quiero ser muy especifico con lo que veo, aqui quiero ver metricas delo que tengo en el resto de la app, asi que aqui te dare libertad de elegir que se pondra.

PUBLICACIONES:
Desde esta funcion de la app debo de poder: Crear, Ver, Eliminar y editar las publicaciones. Ademas de programar publicaciones para diferentes dias.

Las publicaciones actualmente son subastas y creo que las estamos alojando en supabase en vez de agarrarlas siempre desde la api, aqui no se si sea mejor solo usar supabase para autentificar al usuario y lo demas guardarlo en almacenamiento interno del telefono como cache, aqui podemos debatirlo.

Sobre ver las publicacion en la app tengo el sistema de cards el cual me gusta para ver las publicaciones, la idea es que las publicaciones sean visibles con info general, porque aveces me gusta ver cuando llevo ganado en tal subasta e igual tambien sirve para metricas como decir ganaste tanto esta semana con la subastas, usualmente el domingo hago un recuento de cuanto dinero saque en los pedidos y subastas. Sobre lo que llevamos hasta ahorita aqui no hay quejas sobre funcionabilidad, aunque hay cosas que se pueden mejorar, de momento todo funciona bien.

COMENTARIOS:
Fuera de lo que te explique de los comentarios arriba de como deben de ser creo que no falta nada, solo faltaria que en automatico se manden los recordatorios

MENSAJES:
Esta implementacion no se que tan efectiva fue porque mi idea original era usarlo como un messenger pero mientras mas la uso mas limitaciones veo, por ejemplo si no hay actvidad en 24h se cierra el chat y ya no puedo usar la API para mandar mensajes desde la app, pero hay un caso de uso que me sirve que es crear pedido desde chat el cual lo uso cuando me preguntan por cartas o publico cartas generales sin que sean subastas, les pido que me manden inbox y ahi les creo el pedido directamente. aunque creo que habias dicho algo de almacenar el ID, pero inicialmenten o tendria de donde tomarlo si no es por aqui, asi que en esta parte no se si dejarla o no, otra idea que se me ocurre es que en clientes cuando una persona mande mensaje jale el nombre y el ID, lo cree como cliente automaticamente. Pero eso no se si es posible, seria testearlo desde terminal de la api o desde el backend de supabase antes de implementarlo, ademas de ver si es optimo.

CLIENTES:
Aqui con este flujo se crearian ahora en automatico asi que las funciones de crear manual estarian desactivadas.

SUBASTAS:
Al anunciar un ganador, no se puede ver la info del que gano el comentario asi que de momento lo que se hace es que se debe poner en una lista, en donde solo estan los articulos de la subasta que fueron pujados, los que no recibieron puja pues se excluyen de esta lista.

Ahora lo que sigue es asignar manualmente a los usuarios la subasta que ganaron, para esto lo que pienso hacer es agregar una funcion extra en subastas, como vez en subastas puedo abrir para ver los articulos y hasta ahi pero cuando la subasta termina y pase a revision, se podra dar tap a la subasta, elegir en la lista de clientes (esto considerando que se puede guardar el id y nombre del cliente cuando envian mensaje). Asignarle la subasta ganadora a el, pero tambien debo poder seleccionar varias subastas, porque aveces pasa que la misma persona gana varias subastas, si eso pasa todas se suman, es decir, un pedido puede tener muchas fotos/articulos, y al final todo se suma, digamos si son 3 subastas y suman 30 entre las 3, se pondra 30 como el costo de todo el pedido, pero si esa persona participa en otra subasta y se le asigna, pasara lo mismo, esa subasta se le acumula, esta parte me la imagino que salen todos los articulos, al darle tap, me da un pop up bastante grande donde me deja elegir al cliente que la gano, lo selecciono y de ahi se cierra el pop out, ese articulo dentro de la card aparece el nombre y foto del usuario, en caso de tener foto, sino se pudo extraer foto pues solo nombre, de ahi me deja continuar y arriba a la derecha me debe salir el boton guardar, asi cuando termine de asignar, y guarde, pasara lo siguiente, esos artculos que guarde desaprecen de la lista de disponibles o por asignar porque ya los puse, pero los que sigan pendientes de confirmar pues ahi quedan, cuando la subasta ya no tenga por asignar pedidos pasa a completados. De ahi cuando termina de actualizar los articulos, se manda mensaje de confirmacion de pedido a la persona que gano la subasta, en ese mensaje de confirmacion van todas las fotos que gano y la suma de todas las cantidades. el detalle es que me preocupa porque segun se cierra la ventana en 24h y que pasa si el usuario ya esta registrado, hago el mensaje de confirmacion pero como no esta abierto el chat, pues no le llega el mensaje o hay formas de evadirlo? 

con la ruta: 1161721903696435/conversations?fields=id,participants,updated_time

obtuvimos el id en las conversaciones de messenger:
==== Query
  curl -i -X GET \
   "https://graph.facebook.com/v25.0/1161721903696435/conversations?fields=id%2Cparticipants%2Cupdated_time&access_token=<access token sanitized>"
==== Access Token Info
  {
    "perms": [
      "email",
      "pages_show_list",
      "business_management",
      "pages_messaging",
      "pages_read_engagement",
      "pages_manage_metadata",
      "pages_read_user_content",
      "pages_manage_posts",
      "pages_manage_engagement",
      "public_profile"
    ],
    "page_id": 1161721903696435,
    "user_id": "27252754577723299",
    "app_id": 2565886913849368
  }
==== Parameters
- Query Parameters


  {
    "fields": "id,participants,updated_time"
  }
- POST Parameters


  {}
==== Response
  {
    "data": [
      {
        "id": "t_1038486335315086",
        "participants": {
          "data": [
            {
              "name": "Eche Echeagaray",
              "email": "26508222372187174@facebook.com",
              "id": "26508222372187174"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-26T01:13:24+0000"
      },
      {
        "id": "t_916865964752400",
        "participants": {
          "data": [
            {
              "name": "Saii Saii",
              "email": "27008089395531804@facebook.com",
              "id": "27008089395531804"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-26T00:17:48+0000"
      },
      {
        "id": "t_1561168832406504",
        "participants": {
          "data": [
            {
              "name": "José Luis Martinez",
              "email": "27483171181299886@facebook.com",
              "id": "27483171181299886"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-25T23:20:27+0000"
      },
      {
        "id": "t_907973022325269",
        "participants": {
          "data": [
            {
              "name": "Adrian Bañuelos",
              "email": "27215550761400227@facebook.com",
              "id": "27215550761400227"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-25T23:19:03+0000"
      },
      {
        "id": "t_1543141853879403",
        "participants": {
          "data": [
            {
              "name": "YoSoy AstroKid",
              "email": "27169462049391745@facebook.com",
              "id": "27169462049391745"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-25T23:15:09+0000"
      },
      {
        "id": "t_1330761045907049",
        "participants": {
          "data": [
            {
              "name": "Brian Nayit",
              "email": "27882073954751335@facebook.com",
              "id": "27882073954751335"
            },
            {
              "name": "Johann Vega",
              "email": "1161721903696435@facebook.com",
              "id": "1161721903696435"
            }
          ]
        },
        "updated_time": "2026-06-24T02:09:22+0000"
      }
    ],
    "paging": "--sanitized--"
  }
==== Debug Information from Graph API Explorer
- https://developers.facebook.com/tools/explorer/?method=GET&path=1161721903696435%2Fconversations%3Ffields%3Did%2Cparticipants%2Cupdated_time&version=v25.0

los mensajes de utilidad se pueden usar con esta ruta:
1161721903696435/message_templates

no hay templeate creado, se debe crear y de ahi avanzamos

aprobamos uno de ejemplo con esto:
{
  "id": "36668741739406727",
  "status": "APPROVED",
  "category": "UTILITY"
}

{
  "name": "pedido_confirmado_v2",
  "language": "es_MX",
  "category": "UTILITY",
  "components": [
    {
      "type": "BODY",
      "text": "Tu pedido de subasta quedó confirmado por {{1}}. Entrega: {{2}}.",
      "example": {
        "body_text": [
          [
            "$50",
            "Mundo Divertido"
          ]
        ]
      }
    }
  ]
}

se hizo pruebas para enviar a un usuario de prueba y utilizamos:
1161721903696435/messages
{
  "recipient": {
    "id": "27548494861504939"
  },
  "message": {
    "template": {
      "name": "pedido_confirmado_v2",
      "language": {
        "code": "es_MX"
      },
      "components": [
        {
          "type": "BODY",
          "parameters": [
            {
              "type": "text",
              "text": "$50"
            },
            {
              "type": "text",
              "text": "Mundo Divertido"
            }
          ]
        }
      ]
    }
  }
}

los pedidos hay que verlos mas como un carrito al que conforme pasan los dias o semanas se le anexan mas subastas/pedidos

otra cosa es que debemos ver una forma de organizar mis pedidos en fisico que sea consistente con lo digital, osea una metodologia para acomodar, ahorita tengo una etb y separadores y usualmente dedico el sabado a organizar los pedidos asi que si la plataforma tiene una forma de organizar los pedidos que ayude a que la organizacion sea mas rapida por alguna metodologia u orden a seguir, te escucho