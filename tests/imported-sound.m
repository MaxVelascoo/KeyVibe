#import "../src/ImportedSound.h"
static BOOL fixture(NSURL *url,double rate,unsigned channels,double duration,BOOL silent) {
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:channels];
    AVAudioPCMBuffer *b=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(unsigned)(duration*rate)];b.frameLength=b.frameCapacity;
    for(unsigned ch=0;ch<channels;ch++)for(unsigned i=0;i<b.frameLength;i++)b.floatChannelData[ch][i]=silent?0:sin(i*2*M_PI*440/rate)*.7;
    NSMutableDictionary *settings=[format.settings mutableCopy];settings[AVLinearPCMIsNonInterleaved]=@NO;
    NSError *error=nil;AVAudioFile *file=[[AVAudioFile alloc] initForWriting:url settings:settings error:&error];
    return file && [file writeFromBuffer:b error:&error];
}
int main(void){@autoreleasepool{
    NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    int result=0;
    for(unsigned channels=1;channels<=2;channels++)for(unsigned r=0;r<2;r++){
        double rate=r?48000:44100;NSURL *url=[dir URLByAppendingPathComponent:[NSString stringWithFormat:@"sample-%u-%u.wav",channels,r]];
        if(!fixture(url,rate,channels,.1,NO)){result=1;break;}
        NSError *error=nil;AVAudioPCMBuffer *b=loadSound(url,&error);
        if(!b || b.frameLength!=4800 || b.format.channelCount!=1 || b.format.sampleRate!=48000){result=2;break;}
        double energy=0;for(unsigned i=0;i<b.frameLength;i++){double x=b.floatChannelData[0][i];if(!isfinite(x)||fabs(x)>.851)result=3;energy+=x*x;}
        if(energy<1 || b.floatChannelData[0][0]!=0 || b.floatChannelData[0][4799]!=0)result=4;
    }
    NSURL *aiff=[dir URLByAppendingPathComponent:@"sample.aiff"];
    if(!fixture(aiff,44100,1,.1,NO)||!loadSound(aiff,NULL))result=8;
    NSURL *longURL=[dir URLByAppendingPathComponent:@"long.wav"],*silent=[dir URLByAppendingPathComponent:@"silent.wav"],*invalid=[dir URLByAppendingPathComponent:@"invalid.wav"];
    if(!fixture(longURL,48000,1,1.1,NO)||!fixture(silent,48000,1,.1,YES))result=5;
    [@"not an audio file" writeToURL:invalid atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    for(NSURL *url in @[longURL,silent,invalid]){NSError *error=nil;if(loadSound(url,&error)||!error)result=6;}
    [NSFileManager.defaultManager removeItemAtURL:dir error:NULL];
    if(result)fprintf(stderr,"FAILED import test %d\n",result);
    else puts("OK: WAV/AIFF; mono/estéreo; 44,1/48 kHz; fades; rechazo de silencio, archivos inválidos y duración excesiva.");
    return result;
}}
