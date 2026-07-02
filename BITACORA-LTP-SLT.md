# Guia practica: LTP, agTICKET y mercado secundario WRA

Esta bitacora explica la mecanica del caso de estudio Lending Tango Parana desde el punto de vista del alumno. No busca cubrir todos los detalles internos del contrato, sino mostrar que firma cada actor, que recibe y que queda documentado.

## Actores

```text
Administrador / multisig
```

Carga la operacion, crea el ticket, lo emite, aporta liquidez y aprueba SLT.

```text
Tomador / Cooperativa o Logistica portuaria
```

Recibe el ticket, decide bloquearlo, usa el recibo como garantia y toma el prestamo. En SLT tambien firma la ejecucion final.

```text
Auditor / Control
```

Lee estados, revisa hashes en Arbiscan y puede activar el fusible de pausa si la wallet tiene permisos.

## Flujo LTP principal

El LTP es el ticket primario. Documenta la primera operacion.

Ejemplo:

```text
Molinos emite un LTP para AFRA.
El LTP documenta un activo agroindustrial, un monto, una wallet receptora, un vencimiento y una referencia legal.
AFRA usa ese ticket para generar una garantia operativa.
```

## Paso a paso simple

### 1. Crear ticket LTP

Lo firma:

```text
Administrador / multisig
```

Que hace:

```text
Crea el registro del ticket dentro de AgroTicket1155.
Todavia no lo manda al tomador.
```

En el panel:

```text
Administrador -> Crear ticket LTP
```

Resultado:

```text
Ticket ID creado
Hash de transaccion visible
```

### 2. Emitir ticket

Lo firma:

```text
Administrador / multisig
```

Que hace:

```text
Manda el ERC1155 LTP a la wallet receptora del tomador.
```

En el panel:

```text
Administrador -> Emitir ticket
```

Resultado:

```text
La wallet del tomador recibe el LTP.
```

### 3. Bloquear LTP en vault

Lo firma:

```text
Tomador
```

Que hace:

```text
El tomador entrega el LTP al vault.
El vault lo guarda bloqueado.
```

En el panel:

```text
Tomador -> Bloquear LTP
```

Por que existe este paso:

```text
Evita que el mismo ticket se use dos veces.
Si el LTP queda libre en la wallet, podria intentar financiarse en otro lugar con el mismo documento.
```

Resultado:

```text
El LTP queda inmovilizado en AgroTicketReceiptVault.
El tomador recibe 1 agTICKET.
```

### 4. Depositar agTICKET como colateral

Lo firma:

```text
Tomador
```

Que hace:

```text
El tomador aprueba el agTICKET al LendingProtocol.
Luego deposita ese agTICKET como garantia.
```

En el panel:

```text
Tomador -> Depositar agTICKET
```

Resultado:

```text
El LendingProtocol registra 1 agTICKET como colateral del tomador.
```

### 5. Liquidez aUSD disponible

Lo firma, si hace falta fondear:

```text
Admin / Molinos
```

Que hace:

```text
Molinos aporta aUSD al protocolo para que haya liquidez disponible.
```

En el panel:

```text
Admin / Molinos -> Fondear aUSD
```

Nota:

```text
Si ya habia liquidez de una operacion anterior, este paso puede aparecer como disponible aunque no se ejecute de nuevo.
```

### 6. Pedir aUSD

Lo firma:

```text
Tomador
```

Que hace:

```text
El tomador pide aUSD contra el agTICKET depositado.
El protocolo revisa limite colateral y liquidez disponible.
```

En el panel:

```text
Tomador -> Pedir aUSD
```

Resultado:

```text
La wallet del tomador recibe aUSD.
La deuda queda registrada en LendingProtocol.
```

### 7. Revisar hashes

Lo puede hacer:

```text
Admin, tomador, auditor o alumno
```

Que hace:

```text
Lee la linea de vida on-chain.
Abre los hashes en Arbiscan.
Comprueba que cada paso fue firmado por la wallet correcta.
```

## Resumen del flujo LTP

```text
1. Admin crea LTP
2. Admin emite LTP al tomador
3. Tomador bloquea LTP en vault
4. Vault emite 1 agTICKET
5. Tomador deposita agTICKET como colateral
6. Administrador/lender aporta o ya tiene liquidez del token prestado disponible
7. Tomador pide y recibe el token prestado
```

## Caso: logistica portuaria

El modelo de logistica portuaria documenta servicios e infraestructura de la cadena agroindustrial, no necesariamente grano fisico directo.

Puede representar:

```text
transporte
puerto
acopio
seguros
combustible
mantenimiento
fletes
servicios de cosecha
```

La misma operacion puede pedir distintos tokens segun la necesidad:

```text
Si pide aUSD:
busca liquidez estable para costos operativos.

Si pide wTK:
asume una deuda vinculada al precio del trigo tokenizado.
```

Esto permite mostrar que el protocolo no esta limitado a una sola forma de credito. Lo importante es que el mercado tenga liquidez, precio y reglas de riesgo configuradas.

## Que es agTICKET

`agTICKET` no es el documento original.

Es un recibo ERC20 que dice:

```text
Existe un LTP bloqueado en el vault respaldando esta posicion.
```

La relacion conceptual es:

```text
LTP = documento tokenizado original
Vault = caja fuerte donde se bloquea el LTP
agTICKET = recibo financiero del LTP bloqueado
LendingProtocol = acepta agTICKET como colateral
Token prestado = aUSD, wTK, sTK, gTK u otro mercado configurado
```

## SLT: cesion de margen libre del LTP

El SLT es una cesion controlada de margen libre de un LTP ya auditado. No debe confundirse con el LTP ni con el agTICKET ya bloqueado.

```text
LTP = primera operacion documentada
agTICKET = recibo del LTP bloqueado en vault
SLT = subcredito no transferible sobre margen libre del LTP
```

Esta distincion evita una confusion importante:

```text
El SLT no crea una garantia nueva.
El SLT usa capacidad disponible del LTP original.
La deuda sigue atada al borrower primario.
```

La regla educativa que usamos:

```text
Deuda primaria + SLT aprobados <= capacidad maxima del LTP
```

Ejemplo:

```text
Valor del LTP: 100
Advance rate: 65%
Capacidad maxima: 65
Deuda primaria usada: 50
Margen libre: 15
SLT maximo: 15
```

Si el borrower ejecuta un SLT por:

```text
14
```

la deuda total pasa a 64 y sigue dentro del limite.

## Por que el SLT es mas riesgoso

Porque permite que una tercera wallet reciba liquidez sobre el mismo LTP original. Si no se controla, podria aparecer una cascada de credito.

Riesgo:

```text
Si se permite mas de un SLT sobre el mismo LTP, se duplica margen.
Si el administrador pudiera ejecutar solo, podria empujar deuda sin firma del borrower.
Si el SLT fuera transferible, se vuelve dificil auditar quien asume cada riesgo.
```

Por eso el modelo separa:

```text
LTP primario
SLT no transferible
Firma del borrower primario
Aprobacion del administrador
```

Y bloquea duplicidad por LTP.

## Como leer el SLT en el panel

Para un SLT sobre margen libre del LTP:

```text
LTP base para SLT: ticket original
Deuda actual del LTP: deuda primaria ya tomada
Monto solicitado SLT: lo que se quiere ceder a wallet 3
Monto aprobado SLT: lo que aprueba el administrador
Wallet 3: receptor del token prestado
```

Ejemplo:

```text
Capacidad LTP: 65.000
Deuda actual: 50.000
Margen libre: 15.000
SLT solicitado: 15.000
SLT aprobado: 14.000
```

Lectura:

```text
El borrower puede ejecutar 14.000 hacia wallet 3.
La deuda total sube a 64.000.
El LTP sigue dentro de su limite.
```

Ejemplo rechazable:

```text
Capacidad LTP: 65.000
Deuda actual: 60.000
SLT solicitado: 10.000
```

Lectura:

```text
Solo quedan 5.000 de margen libre.
El SLT deberia revertir o ser rechazado.
```

## Idea central para el alumno

El LTP permite entender la primera operacion:

```text
Documento -> vault -> recibo -> colateral -> prestamo
```

El SLT permite estudiar la cesion controlada de margen:

```text
LTP auditado -> margen libre -> wallet 3 recibe liquidez -> deuda total sigue en borrower primario
```

La leccion principal:

```text
No todo margen disponible debe poder duplicarse.
El protocolo debe distinguir entre deuda primaria, margen libre y subcredito SLT.
```
