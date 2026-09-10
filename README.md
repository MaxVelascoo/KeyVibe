# KeyVibe

Prototipo nativo de macOS para el teclado integrado de un MacBook Apple Silicon. Estima la intensidad de las pulsaciones con las vibraciones del acelerómetro y reproduce sonidos sintetizados localmente.

## Abrir

Abre `build/KeyVibe.app`. KeyVibe aparece como un icono de teclado en la barra de menús y no abre una ventana ni ocupa espacio en el Dock. Pulsa el icono para mostrar el panel compacto con todos los controles; vuelve a pulsarlo o haz clic fuera para cerrarlo.

Pulsa **Permitir** y activa **KeyVibe** en Ajustes del Sistema → Privacidad y seguridad → Monitorización de entrada. Si macOS pide salir y volver a abrir, hazlo. El botón **Probar** funciona sin ese permiso.

El medidor responde a las vibraciones incluso antes de conceder acceso al teclado. Escribe suave y después con mayor intensidad normal; ajusta Sensibilidad si todo suena suave o fuerte. No hace falta golpear el portátil. Volumen inicial: 35 %.

El panel incluye activación, sonido, volumen, sensibilidad, medidor, estado, importación y salida. Al pausar, el icono del teclado cambia por un símbolo de pausa. No se añade al inicio de sesión.

## Añadir sonidos

El selector incluye Clásico, Profundo, Cristal, Madera, Burbuja, Retro, Máquina y Papel. Son timbres sintetizados; no son grabaciones de modelos concretos de switches.

Pulsa **Importar sonido…** y elige un archivo **WAV o AIFF de hasta un segundo**. Idealmente, usa un clic de 30–150 ms y recorta el silencio al principio. La app convierte a mono a 48 kHz, suaviza los extremos y reduce picos excesivos. La intensidad de la pulsación ajusta el volumen de la grabación; no inventa tomas de distinta fuerza.

La grabación se copia a `~/Library/Application Support/KeyVibe/Sounds/`, aparece como **Grabación · nombre** y se conserva al reiniciar, aunque muevas el original. Si el nombre ya existe se añade un sufijo. La selección también se recuerda. Para quitar una grabación, cierra KeyVibe, elimina su copia de esa carpeta y vuelve a abrirla.

Para un sonido más realista, usa un pack completo; cada archivo importado de forma individual sigue siendo una opción independiente.

### Packs completos

KeyVibe detecta automáticamente los packs instalados en `Haptyk.app` y los muestra como **Pack · nombre**. Los lee directamente y no modifica la aplicación original. Si Haptyk deja de estar instalado, esos packs dejan de aparecer.

Cada pack puede tener cuatro intensidades (`soft`, `medium`, `hard` y `slam`), variantes aleatorias para evitar repeticiones, sonidos propios para letras, espacio, Intro, borrar, flechas, modificadores y funciones, y sonidos opcionales al soltar la tecla. El nombre, autor y licencia se leen del `pack.json`.

Pulsa **Importar pack…** para conservar una copia independiente en `~/Library/Application Support/KeyVibe/Packs/`. Puedes elegir una carpeta con un `pack.json` o una carpeta que contenga varios packs. KeyVibe admite WAV y AIFF de hasta dos segundos y bloquea rutas del manifiesto que salgan de la carpeta del pack.

Los 16 packs detectados en Haptyk declaran licencia MIT en sus manifiestos y atribuyen las grabaciones a ClickClack Contributors o Mechvibes Contributors. Conserva el `pack.json` y los avisos de licencia al copiar o distribuir un pack.

## Compilar y verificar

Requiere las herramientas de línea de comandos de Xcode. Sin dependencias externas.

```sh
./build.sh
./build/sensor-probe
open build/KeyVibe.app
```

La firma local usa un requisito designado estable basado en el identificador de KeyVibe. Así macOS puede reconocer las siguientes compilaciones como la misma aplicación y conservar el permiso de Monitorización de entrada.

La importación se comprueba con `./test.sh`: WAV/AIFF, mono/estéreo, conversión de 44,1/48 kHz, rechazo de archivos inválidos y validación de los 16 packs y sus 680 grabaciones.

`build.sh` compila, firma localmente y comprueba los 216 sonidos (valores finitos, señal no vacía y sin clipping), además de la ventana temporal del detector. `sensor-probe` lee durante tres segundos, muestra frecuencia y pico, y cierra el dispositivo. No captura teclado ni pide administrador.

## Funcionamiento

- Cocoa / Objective-C, IOKit HID y AVAudioEngine.
- Sensor AppleSPUHIDDevice, usage page 0xFF00, usage 3. Informes de 22 bytes; ejes Q16 en offsets 6, 10 y 14.
- Intensidad estimada mediante la diferencia entre muestras consecutivas de los tres ejes. Ventana de hasta 18 ms antes y 6 ms después de la pulsación; cuatro niveles en los packs y sensibilidad ajustable.
- 16 voces de audio. Los sonidos incluidos ofrecen 8 timbres sintetizados, 3 intensidades, 3 grupos de teclas y 3 variantes. Los packs ofrecen hasta 4 intensidades, 8 grupos, variantes y sonidos de liberación.
- Monitor de eventos de solo escucha. Solo usa el código numérico de tecla y si se pulsa o suelta para elegir un grupo de sonido. No obtiene cadenas ni guarda pulsaciones. No hay red ni telemetría.
- Preferencias de volumen, timbre y sensibilidad en NSUserDefaults.

## Límites del prototipo

La presencia de datos del sensor se verificó en este MacBook Air M4: 2412 muestras en tres segundos (aprox. 804 Hz), sin administrador. Falta calibrar la respuesta al tacto con el usuario; la precisión y latencia audible no se han medido. El acceso al sensor usa una interfaz no documentada y puede cambiar con macOS.

Las vibraciones de la mesa, los altavoces y otras pulsaciones próximas pueden influir. Usar auriculares ayuda a aislar las vibraciones de los altavoces; Bluetooth puede añadir retraso. El teclado externo no es el objetivo de este prototipo. Si el sensor deja de enviar datos, se indica en pantalla y se usa sonido de intensidad fija. La entrada segura de macOS puede impedir detectar teclas en campos protegidos.

La firma es ad hoc para desarrollo local: recompilar puede requerir volver a conceder el permiso. No hay distribución notarizada ni instalador.

## Referencia técnica

El formato del sensor se basa en la documentación pública de [apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer), de olvvier, publicada con licencia MIT. Esta implementación es independiente. El ejecutable de KeyVibe no incorpora sonidos ni código de Haptyk; puede leer packs externos mediante sus manifiestos.
