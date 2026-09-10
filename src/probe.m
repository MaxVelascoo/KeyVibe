#import "Sensor.h"
int main(void){@autoreleasepool{puts(startSensor().UTF8String);if(!sensorDevice)return 3;double start=nowSeconds();CFRunLoopRunInMode(kCFRunLoopDefaultMode,3,false);printf("Muestras: %lu; frecuencia: %.0f Hz; pico: %.6f g\n",sampleCount,sampleCount/3.,peakBetween(start,nowSeconds()));stopSensor();return sampleCount?0:4;}}
