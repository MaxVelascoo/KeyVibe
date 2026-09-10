#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDevice.h>
#import <mach/mach_time.h>
#include <math.h>
// Protocol documented at github.com/olvvier/apple-silicon-accelerometer (MIT).
static IOHIDDeviceRef sensorDevice;
static uint8_t sensorBuffer[4096];
static unsigned long sampleCount;
static double lastXYZ[3], sampleTimes[2048], impacts[2048];
static double nowSeconds(void) { static mach_timebase_info_data_t tb; if(!tb.denom)mach_timebase_info(&tb); return mach_absolute_time()*(double)tb.numer/tb.denom/1e9; }
static int registryInt(io_service_t s, CFStringRef key) {
    CFTypeRef ref=IORegistryEntryCreateCFProperty(s,key,0,0); int v=0;
    if(ref){if(CFGetTypeID(ref)==CFNumberGetTypeID())CFNumberGetValue(ref,kCFNumberIntType,&v);CFRelease(ref);}return v;
}
static void sensorReport(void *ctx, IOReturn result, void *sender, IOHIDReportType type, uint32_t rid, uint8_t *bytes, CFIndex len) {
    if(result || len!=22)return;
    double sum=0; for(int i=0;i<3;i++){int32_t n;memcpy(&n,bytes+6+i*4,4);double v=n/65536.0;if(sampleCount)sum+=(v-lastXYZ[i])*(v-lastXYZ[i]);lastXYZ[i]=v;}
    unsigned index=sampleCount%2048;sampleTimes[index]=nowSeconds();impacts[index]=sqrt(sum);sampleCount++;
}
static NSString *startSensor(void) {
    io_iterator_t it=0;IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleSPUHIDDevice"),&it);
    io_service_t s;while((s=IOIteratorNext(it))){
        if(registryInt(s,CFSTR("PrimaryUsagePage"))==0xff00 && registryInt(s,CFSTR("PrimaryUsage"))==3)sensorDevice=IOHIDDeviceCreate(0,s);
        IOObjectRelease(s);if(sensorDevice)break;
    }if(it)IOObjectRelease(it);
    if(!sensorDevice)return @"Sensor no encontrado";
    IOReturn result=IOHIDDeviceOpen(sensorDevice,0);
    if(result){CFRelease(sensorDevice);sensorDevice=NULL;return [NSString stringWithFormat:@"Sensor: acceso denegado (0x%x)",result];}
    IOHIDDeviceRegisterInputReportCallback(sensorDevice,sensorBuffer,sizeof(sensorBuffer),sensorReport,NULL);
    IOHIDDeviceScheduleWithRunLoop(sensorDevice,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
    return @"Sensor abierto; esperando muestras";
}
static double peakBetween(double from, double to) {
    double peak=0;unsigned long start=sampleCount>2048?sampleCount-2048:0;
    for(unsigned long i=start;i<sampleCount;i++){unsigned n=i%2048;if(sampleTimes[n]>=from && sampleTimes[n]<=to)peak=fmax(peak,impacts[n]);}return peak;
}
static void stopSensor(void){if(sensorDevice){IOHIDDeviceUnscheduleFromRunLoop(sensorDevice,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);IOHIDDeviceClose(sensorDevice,0);CFRelease(sensorDevice);sensorDevice=NULL;}}
