# Lending Tango Parana: ticket token de trigo para credito productivo

Estoy trabajando en un caso de estudio llamado **Lending Tango Parana**, un mini protocolo educativo para entender lending, borrowing, oraculos, colateral y liquidaciones usando un activo familiar para LATAM: trigo tokenizado.

La idea del nuevo escenario es simple:

**Molinos Rio Parana** otorga a plazo de 6 meses un ticket token por **10.000 wTK** a la **Asociacion Camioneros de Entre Rios**.

En este modelo:

- `1 wTK = 1 tonelada de trigo`.
- El precio base puede venir de una referencia publica de trigo en USD/bushel.
- El oracle convierte bushel a tonelada.
- Luego se puede expresar el valor en USDC, USDT u otra estable.
- El ticket se emite hacia una wallet de ejemplo.
- Ese ticket representa una posicion verificable: quien lo emite, quien lo recibe, plazo, cantidad, precio de referencia, valor nocional y posible salida secundaria.

Ejemplo conceptual:

1. Molinos emite un ticket por 10.000 wTK.
2. El protocolo calcula el valor nocional usando el precio oracle.
3. El receptor podria usar ese ticket como respaldo para obtener liquidez estable en un mercado secundario auditado.
4. Esa liquidez podria transformarse en capital operativo: combustible, mantenimiento, adelanto de fletes o incluso la compra de un camion.

La parte mas didactica del ejemplo es el riesgo:

Si la asociacion recibe o usa `wTK`, tambien debe pensar su deuda en `wTK`.

- Si el trigo sube, la deuda medida en USDT/USDC sube.
- Si el trigo baja, devolver los mismos `wTK` cuesta menos medido en estable.
- Por eso puede existir una posicion saludable desde liquidacion, pero bloqueada para tomar mas deuda porque ya supero el factor colateral.

Ese punto ayuda a separar dos conceptos que suelen mezclarse:

- **Factor colateral:** cuanto se puede pedir.
- **Umbral de liquidacion:** cuando ya se puede liquidar.

No estoy planteando esto como producto financiero listo para operar. Es un laboratorio tecnico para estudiar como se conectan:

- contratos inteligentes;
- oraculos de precio;
- activos del mundo real;
- mercados secundarios;
- trazabilidad fiscal;
- auditoria;
- gestion de riesgo.

Lo interesante aparece cuando el lector puede ver el flujo completo:

**activo fisico -> token wTK -> precio oracle -> ticket token -> estable -> uso productivo real**

El objetivo del estudio no es hacer algo complejo. Es justo lo contrario: construir una interfaz y una logica lo suficientemente claras como para que cualquier persona pueda entender que esta pasando antes de mirar el contrato.

Lending criollo, pero con matematica visible.
