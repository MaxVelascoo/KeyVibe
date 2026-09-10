#import <AVFoundation/AVFoundation.h>
#include <math.h>
static NSError *soundError(NSString *message) {
    return [NSError errorWithDomain:@"KeyVibe.Sound" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
// Decode short local samples once, outside the playback path. Mix to mono and
// resample to the engine's 48 kHz using linear interpolation.
static AVAudioPCMBuffer *loadSoundWithLimit(NSURL *url, double maxDuration, NSError **error) {
    AVAudioFile *file=[[AVAudioFile alloc] initForReading:url commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:error];
    if(!file)return nil;
    double rate=file.processingFormat.sampleRate;
    unsigned channels=file.processingFormat.channelCount;
    if(rate<8000 || rate>192000 || channels<1 || channels>8 || file.length<2 || file.length>rate*maxDuration){
        if(error)*error=soundError([NSString stringWithFormat:@"Usa un sonido de entre dos muestras y %.1f segundos, con hasta 8 canales y frecuencia de 8–192 kHz.",maxDuration]);return nil;
    }
    AVAudioPCMBuffer *source=[[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:(AVAudioFrameCount)file.length];
    if(![file readIntoBuffer:source error:error])return nil;
    if(source.frameLength<2){if(error)*error=soundError(@"El archivo no contiene audio suficiente.");return nil;}
    for(unsigned ch=0;ch<channels;ch++)for(unsigned i=0;i<source.frameLength;i++){
        if(!isfinite(source.floatChannelData[ch][i])){if(error)*error=soundError(@"El archivo contiene valores de audio inválidos.");return nil;}
    }
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
    unsigned frames=(unsigned)floor(source.frameLength*48000./rate);
    AVAudioPCMBuffer *out=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];out.frameLength=frames;
    float *data=out.floatChannelData[0];double peak=0;
    for(unsigned i=0;i<frames;i++){
        double p=i*rate/48000.;unsigned a=MIN((unsigned)p,source.frameLength-1),b=MIN(a+1,source.frameLength-1);double fraction=p-a,value=0;
        for(unsigned ch=0;ch<channels;ch++){float *in=source.floatChannelData[ch];value+=(in[a]*(1-fraction)+in[b]*fraction)/channels;}
        data[i]=value;peak=fmax(peak,fabs(value));
    }
    if(peak<.00001){if(error)*error=soundError(@"El sonido queda en silencio al convertirlo a mono. Prueba otra grabación.");return nil;}
    // Keep quiet recordings quiet; attenuate only samples that exceed headroom.
    double gain=peak>.85?.85/peak:1;
    unsigned fade=MIN(96,frames/4);
    for(unsigned i=0;i<frames;i++){
        double edge=fade?fmin(1,fmin(i/(double)fade,(frames-1-i)/(double)fade)):1;
        data[i]*=gain*edge;
    }
    return out;
}
static AVAudioPCMBuffer *loadSound(NSURL *url, NSError **error) {
    return loadSoundWithLimit(url,1,error);
}
static NSArray<NSString *> *styleNames(void) {
    return @[@"Clásico · seco",@"Profundo · grave",@"Cristal · brillante",@"Madera · cálido",@"Burbuja · pop",@"Retro · digital",@"Máquina · metálico",@"Papel · ligero"];
}
