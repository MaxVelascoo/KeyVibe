#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import "Sensor.h"
#import "ImportedSound.h"
#import "SoundPack.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Built-in sounds are synthesized locally. No keyboard text is stored or transmitted.
static AVAudioPCMBuffer *makeClick(AVAudioFormat *format, int style, int tier, int group, int variant) {
    const double sr=48000, duration=.085;
    AVAudioPCMBuffer *b=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)(sr*duration)];
    b.frameLength=b.frameCapacity; float *out=b.floatChannelData[0];
    uint32_t rng=12345+style*907+tier*127+group*37+variant*1777;
    const double bodies[]={430,230,850,340,520,680,1150,460};
    double body=bodies[style];
    body*=group==1?.68:group==2?.83:1;
    body*=1+variant*.018; double low=0;
    for(unsigned i=0;i<b.frameLength;i++) {
        double t=i/sr; rng=rng*1664525u+1013904223u;
        double noise=((rng>>8)/(double)0xffffff)*2-1;
        low+=.23*(noise-low);
        double attack=fmin(1,t/.0004);
        double snap=(noise-low)*exp(-t/(.0014+tier*.0005))*(.15+tier*.12);
        double thock=sin(2*M_PI*body*t)*exp(-t/(style==1?.015:.008))*.4;
        double rattle=low*exp(-t/.012)*.2;
        double bottom=t>.008?sin(2*M_PI*body*.75*(t-.008))*exp(-(t-.008)/.006)*.12:0;
        double sound=snap+thock+rattle+bottom;
        if(style==3)sound=thock+sin(2*M_PI*body*1.73*t)*exp(-t/.013)*.22+snap*.4;
        if(style==4)sound=sin(2*M_PI*(body*t+95*.009*(1-exp(-t/.009))))*exp(-t/.016)*.6+snap*.18;
        if(style==5)sound=tanh(sin(2*M_PI*body*t)*3)*exp(-t/.008)*.36+snap*.2;
        if(style==6)sound=snap*1.2+(sin(2*M_PI*body*t)+.4*sin(2*M_PI*body*2.71*t))*exp(-t/.017)*.21+bottom;
        if(style==7)sound=(noise-low)*exp(-t/.006)*.35+low*exp(-t/.023)*.28;
        double x=attack*sound*(.45+tier*.22);
        out[i]=(float)fmax(-.95,fmin(.95,x));
    } return b;
}
@interface KeyVibe : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@property NSPopover *popover;
@property NSView *contentView;
@property NSStatusItem *statusItem;
@property NSTextField *sensorLabel, *keyboardLabel, *levelLabel;
@property NSLevelIndicator *meter;
@property NSSlider *volume, *sensitivity;
@property NSButton *enabled;
@property NSPopUpButton *style;
@property AVAudioEngine *engine;
@property NSMutableArray<AVAudioPlayerNode *> *voices;
@property NSMutableArray<AVAudioPCMBuffer *> *sounds;
@property NSMutableArray<AVAudioPCMBuffer *> *importedSounds;
@property NSMutableArray<NSString *> *importedNames;
@property NSMutableArray<KVSoundPack *> *packs;
@property BOOL choosingSound;
@property NSTimer *timer;
@property NSString *sensorStatus;
@property unsigned voiceIndex;
@property double lastKeyTime;
@property CFMachPortRef tap;
@property CFRunLoopSourceRef tapSource;
- (void)key:(CGKeyCode)key down:(BOOL)down;
@end
static CGEventRef onKey(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    KeyVibe *app=(__bridge KeyVibe *)context;
    if(type==kCGEventTapDisabledByTimeout || type==kCGEventTapDisabledByUserInput){if(app.tap)CGEventTapEnable(app.tap,true);return event;}
    if((type==kCGEventKeyDown || type==kCGEventKeyUp) && !CGEventGetIntegerValueField(event,kCGKeyboardEventAutorepeat))
        [app key:(CGKeyCode)CGEventGetIntegerValueField(event,kCGKeyboardEventKeycode) down:type==kCGEventKeyDown];
    return event;
}
@implementation KeyVibe
- (NSTextField *)label:(NSString *)text x:(double)x y:(double)y size:(double)size {
    NSTextField *v=[NSTextField labelWithString:text];v.font=[NSFont systemFontOfSize:size];
    v.frame=NSMakeRect(x,y,356,26);[self.contentView addSubview:v];return v;
}
- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *b=[NSButton buttonWithTitle:title target:self action:action];b.frame=frame;[self.contentView addSubview:b];return b;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    [d registerDefaults:@{@"volume":@.35,@"sensitivity":@1.,@"style":@0,@"enabled":@YES}];
    NSViewController *controller=[NSViewController new];
    self.contentView=[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,520)];controller.view=self.contentView;
    self.popover=[NSPopover new];self.popover.contentViewController=controller;self.popover.contentSize=NSMakeSize(400,520);self.popover.behavior=NSPopoverBehaviorTransient;self.popover.animates=YES;self.popover.delegate=self;
    NSTextField *title=[self label:@"KeyVibe" x:22 y:474 size:23];title.font=[NSFont boldSystemFontOfSize:23];
    [self label:@"Tu teclado, con carácter." x:22 y:447 size:13];
    self.enabled=[NSButton checkboxWithTitle:@"Sonido activado" target:self action:@selector(save:)];self.enabled.frame=NSMakeRect(22,406,220,28);self.enabled.state=[d boolForKey:@"enabled"]?NSControlStateValueOn:NSControlStateValueOff;[self.contentView addSubview:self.enabled];
    [self label:@"Sonido" x:22 y:363 size:13];
    self.style=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(108,361,270,28) pullsDown:NO];
    [self.style addItemsWithTitles:styleNames()];[self.style selectItemAtIndex:MAX(0,MIN((NSInteger)styleNames().count-1,[d integerForKey:@"style"]))];self.style.target=self;self.style.action=@selector(save:);[self.contentView addSubview:self.style];
    [self label:@"Volumen" x:22 y:320 size:13];
    self.volume=[NSSlider sliderWithValue:[d doubleForKey:@"volume"] minValue:0 maxValue:1 target:self action:@selector(save:)];self.volume.frame=NSMakeRect(108,325,270,20);[self.contentView addSubview:self.volume];
    [self label:@"Sensibilidad" x:22 y:278 size:13];
    self.sensitivity=[NSSlider sliderWithValue:[d doubleForKey:@"sensitivity"] minValue:.2 maxValue:5 target:self action:@selector(save:)];self.sensitivity.frame=NSMakeRect(108,283,270,20);[self.contentView addSubview:self.sensitivity];
    [self label:@"Súbela si todas las pulsaciones suenan suaves." x:108 y:255 size:10];
    self.meter=[[NSLevelIndicator alloc] initWithFrame:NSMakeRect(22,224,356,16)];self.meter.levelIndicatorStyle=NSLevelIndicatorStyleContinuousCapacity;self.meter.minValue=0;self.meter.maxValue=1;self.meter.warningValue=.65;self.meter.criticalValue=.9;[self.contentView addSubview:self.meter];
    self.levelLabel=[self label:@"Escribe para probar la intensidad" x:22 y:192 size:12];
    self.sensorLabel=[self label:@"Comprobando acelerómetro…" x:22 y:158 size:11];
    self.keyboardLabel=[self label:@"Teclado: pendiente de permiso" x:22 y:133 size:11];
    [self button:@"Permitir" action:@selector(allowKeyboard:) frame:NSMakeRect(17,91,112,30)];
    [self button:@"Probar" action:@selector(preview:) frame:NSMakeRect(136,91,104,30)];
    [self button:@"Importar sonido…" action:@selector(importSound:) frame:NSMakeRect(247,91,136,30)];
    [self button:@"Salir" action:@selector(quit:) frame:NSMakeRect(17,55,112,28)];
    [self button:@"Importar pack…" action:@selector(importPack:) frame:NSMakeRect(247,55,136,28)];
    [self label:@"Local y privado · no guarda lo que escribes" x:22 y:16 size:10];
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image=[NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"KeyVibe"];
    self.statusItem.button.image.template=YES;self.statusItem.button.toolTip=@"KeyVibe";self.statusItem.button.target=self;self.statusItem.button.action=@selector(togglePopover:);
    [self startAudio];[self restoreSounds];[self restorePacks];[self save:nil];self.sensorStatus=startSensor();
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [[NSWorkspace sharedWorkspace].notificationCenter addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
    dispatch_async(dispatch_get_main_queue(),^{
        if(![self connectKeyboard])CGRequestListenEventAccess();
    });
}
- (void)togglePopover:(id)sender {
    if(self.popover.isShown){[self.popover performClose:sender];return;}
    NSStatusBarButton *button=self.statusItem.button;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
}
- (void)quit:(id)sender {[NSApp terminate:nil];}
- (void)startAudio {
    self.engine=[AVAudioEngine new]; self.voices=[NSMutableArray new];self.sounds=[NSMutableArray new];
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
    for(int style=0;style<(int)styleNames().count;style++)for(int tier=0;tier<3;tier++)for(int group=0;group<3;group++)for(int v=0;v<3;v++)[self.sounds addObject:makeClick(format,style,tier,group,v)];
    for(int i=0;i<16;i++){AVAudioPlayerNode *p=[AVAudioPlayerNode new];[self.engine attachNode:p];[self.engine connect:p to:self.engine.mainMixerNode format:format];[self.voices addObject:p];}
    NSError *error=nil;[self.engine prepare];
    if(![self.engine startAndReturnError:&error]){self.levelLabel.stringValue=[NSString stringWithFormat:@"Audio: %@",error.localizedDescription];return;}
    for(AVAudioPlayerNode *p in self.voices)[p play];
}
- (BOOL)connectKeyboard {
    if(self.tap)return YES;
    if(!CGPreflightListenEventAccess())return NO;
    self.tap=CGEventTapCreate(kCGSessionEventTap,kCGHeadInsertEventTap,kCGEventTapOptionListenOnly,CGEventMaskBit(kCGEventKeyDown)|CGEventMaskBit(kCGEventKeyUp),onKey,(__bridge void *)self);
    if(!self.tap)return NO;
    self.tapSource=CFMachPortCreateRunLoopSource(NULL,self.tap,0);CFRunLoopAddSource(CFRunLoopGetMain(),self.tapSource,kCFRunLoopCommonModes);CGEventTapEnable(self.tap,true);return YES;
}
- (void)allowKeyboard:(id)sender {
    if([self connectKeyboard])return;
    CGRequestListenEventAccess();
    if(![self connectKeyboard])[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
}
- (NSString *)groupForKey:(CGKeyCode)key {
    if(key==49)return @"space";
    if(key==36 || key==76)return @"enter";
    if(key==51 || key==117)return @"delete";
    if(key>=123 && key<=126)return @"arrow";
    if((key>=54&&key<=63)||key==179)return @"modifier";
    if((key>=96&&key<=113)||key==122||key==120||key==118||key==116||key==115||key==119||key==121)return @"function";
    return @"alpha";
}
- (void)key:(CGKeyCode)key down:(BOOL)down {
    if(self.enabled.state!=NSControlStateValueOn || self.choosingSound)return;
    NSInteger packIndex=self.style.indexOfSelectedItem-(NSInteger)styleNames().count-(NSInteger)self.importedSounds.count;
    if(!down){
        if(packIndex>=0 && packIndex<(NSInteger)self.packs.count){
            NSArray *buffers=packReleaseBuffers(self.packs[packIndex],[self groupForKey:key]);
            if(buffers.count)[self playBuffer:buffers[arc4random_uniform((uint32_t)buffers.count)] gain:.72];
        }
        return;
    }
    double time=nowSeconds();double from=fmax(self.lastKeyTime,time-.018);self.lastKeyTime=time;
    NSString *packGroup=[self groupForKey:key];int group=[packGroup isEqual:@"space"]?1:([packGroup isEqual:@"enter"]||[packGroup isEqual:@"delete"]?2:0);
    // Wait 6 ms for impact reports arriving shortly after the keyboard event.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.enabled.state!=NSControlStateValueOn || self.choosingSound)return;
        BOOL live=sampleCount && nowSeconds()-sampleTimes[(sampleCount-1)%2048]<.25;
        double force=live?fmin(1,peakBetween(from,time+.006)*self.sensitivity.doubleValue/.025):.5;
        [self playForce:force group:group packGroup:packGroup];
        self.levelLabel.stringValue=live?[NSString stringWithFormat:@"%@ · intensidad %.0f %%",force<.25?@"Suave":force<.65?@"Media":@"Fuerte",force*100]:@"Sin datos del sensor · sonido de intensidad fija";
    });
}
- (void)playBuffer:(AVAudioPCMBuffer *)buffer gain:(float)gain {
    if(!self.engine.isRunning){NSError *error=nil;if(![self.engine startAndReturnError:&error]){self.levelLabel.stringValue=@"No se ha podido iniciar el audio";return;}for(AVAudioPlayerNode *p in self.voices)[p play];}
    AVAudioPlayerNode *p=self.voices[self.voiceIndex++%self.voices.count];p.volume=self.volume.floatValue*gain;
    [p scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
}
- (void)playForce:(double)force group:(int)group packGroup:(NSString *)packGroup {
    NSInteger selected=self.style.indexOfSelectedItem;
    if(selected<0)return;
    AVAudioPCMBuffer *buffer;float gain=1;
    if(selected<(NSInteger)styleNames().count){
        unsigned tier=force<.25?0:force<.65?1:2;
        unsigned idx=(unsigned)selected*27+tier*9+group*3+arc4random_uniform(3);buffer=self.sounds[idx];
    } else if(selected<(NSInteger)styleNames().count+(NSInteger)self.importedSounds.count) {
        NSUInteger index=selected-styleNames().count;
        buffer=self.importedSounds[index];gain=.3+.7*force;
    } else {
        NSUInteger index=selected-styleNames().count-self.importedSounds.count;if(index>=self.packs.count)return;
        NSString *tier=force<.22?@"soft":force<.50?@"medium":force<.78?@"hard":@"slam";
        NSArray *buffers=packBuffers(self.packs[index],packGroup,tier);if(!buffers.count)return;
        buffer=buffers[arc4random_uniform((uint32_t)buffers.count)];
    }
    [self playBuffer:buffer gain:gain];
}
- (NSURL *)soundsDirectory {
    NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"KeyVibe/Sounds" isDirectory:YES];
}
- (void)restoreSounds {
    self.importedSounds=[NSMutableArray new];self.importedNames=[NSMutableArray new];
    NSURL *directory=[self soundsDirectory];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]){self.levelLabel.stringValue=@"No se puede abrir la colección de sonidos";return;}
    NSArray *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    urls=[urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];}];
    NSString *selected=[NSUserDefaults.standardUserDefaults stringForKey:@"importedSound"];
    unsigned skipped=0;
    for(NSURL *url in urls){
        if(![@[@"wav",@"aif",@"aiff"] containsObject:url.pathExtension.lowercaseString])continue;
        AVAudioPCMBuffer *buffer=loadSound(url,&error);if(!buffer){skipped++;continue;}
        [self.importedSounds addObject:buffer];[self.importedNames addObject:url.lastPathComponent];
        [self.style addItemWithTitle:[@"Grabación · " stringByAppendingString:url.lastPathComponent.stringByDeletingPathExtension]];
        if([selected isEqualToString:url.lastPathComponent])[self.style selectItemAtIndex:self.style.numberOfItems-1];
    }
    if(skipped)self.levelLabel.stringValue=[NSString stringWithFormat:@"%u grabaciones no se han podido cargar",skipped];
}
- (void)importSound:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.allowedContentTypes=@[UTTypeWAV,UTTypeAIFF];panel.allowsMultipleSelection=NO;panel.canChooseDirectories=NO;
    panel.message=@"Elige un WAV o AIFF de hasta 1 segundo. Recorta el silencio inicial para que responda al instante.";
    self.choosingSound=YES;
    [self.popover performClose:nil];
    [panel beginWithCompletionHandler:^(NSModalResponse result){
        self.choosingSound=NO;if(result!=NSModalResponseOK)return;
        NSError *error=nil;AVAudioPCMBuffer *buffer=loadSound(panel.URL,&error);
        NSURL *target=nil;
        if(buffer){
            NSURL *dir=[self soundsDirectory];NSString *stem=panel.URL.lastPathComponent.stringByDeletingPathExtension;
            target=[dir URLByAppendingPathComponent:panel.URL.lastPathComponent];unsigned suffix=2;
            while([NSFileManager.defaultManager fileExistsAtPath:target.path])target=[dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%u).%@",stem,suffix++,panel.URL.pathExtension]];
            if(![NSFileManager.defaultManager copyItemAtURL:panel.URL toURL:target error:&error])buffer=nil;
        }
        if(!buffer){NSAlert *alert=[NSAlert new];alert.messageText=@"No se ha podido importar el sonido";alert.informativeText=error.localizedDescription?:@"Prueba otro archivo WAV o AIFF.";[alert runModal];return;}
        [self.importedSounds addObject:buffer];[self.importedNames addObject:target.lastPathComponent];
        [self.style addItemWithTitle:[@"Grabación · " stringByAppendingString:target.lastPathComponent.stringByDeletingPathExtension]];
        [self.style selectItemAtIndex:self.style.numberOfItems-1];[self save:nil];[self preview:nil];
        self.levelLabel.stringValue=@"Grabación añadida · volumen según la intensidad";
    }];
}
- (NSURL *)packsDirectory {
    NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"KeyVibe/Packs" isDirectory:YES];
}
- (NSArray<NSURL *> *)packRootsAtURL:(NSURL *)url {
    if([NSFileManager.defaultManager fileExistsAtPath:[[url URLByAppendingPathComponent:@"pack.json"] path]])return @[url];
    NSArray *children=[NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *roots=[NSMutableArray new];
    for(NSURL *child in children)if([NSFileManager.defaultManager fileExistsAtPath:[[child URLByAppendingPathComponent:@"pack.json"] path]])[roots addObject:child];
    return [roots sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];}];
}
- (void)restorePacks {
    NSInteger start=(NSInteger)(styleNames().count+self.importedSounds.count);
    while(self.style.numberOfItems>start)[self.style removeItemAtIndex:start];
    self.packs=[NSMutableArray new];NSMutableSet *names=[NSMutableSet new];
    NSURL *local=[self packsDirectory];NSError *directoryError=nil;
    [NSFileManager.defaultManager createDirectoryAtURL:local withIntermediateDirectories:YES attributes:nil error:&directoryError];
    NSArray *sources=@[local,
        [NSURL fileURLWithPath:@"/Applications/Haptyk.app/Contents/Resources/SoundPacks" isDirectory:YES],
        [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Haptyk.app/Contents/Resources/SoundPacks"] isDirectory:YES]];
    NSString *selected=[NSUserDefaults.standardUserDefaults stringForKey:@"selectedPackName"];
    NSUInteger failed=0,totalFiles=0;
    for(NSURL *source in sources)for(NSURL *root in [self packRootsAtURL:source]){
        NSError *error=nil;KVSoundPack *pack=loadPack(root,&error);
        if(!pack){failed++;continue;}
        if([names containsObject:pack.name])continue;
        [names addObject:pack.name];[self.packs addObject:pack];totalFiles+=pack.fileCount;
        [self.style addItemWithTitle:[@"Pack · " stringByAppendingString:pack.name]];
        if([selected isEqualToString:pack.name])[self.style selectItemAtIndex:self.style.numberOfItems-1];
    }
    if(self.packs.count)self.levelLabel.stringValue=[NSString stringWithFormat:@"%lu packs completos · %lu grabaciones cargadas",self.packs.count,totalFiles];
    if(failed)self.levelLabel.stringValue=[NSString stringWithFormat:@"%lu packs cargados; %lu no válidos",self.packs.count,failed];
}
- (void)importPack:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.allowsMultipleSelection=NO;
    panel.message=@"Elige un pack con pack.json o una carpeta que contenga varios packs.";
    NSString *haptyk=@"/Applications/Haptyk.app/Contents/Resources/SoundPacks";
    if([NSFileManager.defaultManager fileExistsAtPath:haptyk])panel.directoryURL=[NSURL fileURLWithPath:haptyk isDirectory:YES];
    self.choosingSound=YES;
    [self.popover performClose:nil];
    [panel beginWithCompletionHandler:^(NSModalResponse result){
        self.choosingSound=NO;if(result!=NSModalResponseOK)return;
        NSArray<NSURL *> *roots=[self packRootsAtURL:panel.URL];
        NSMutableArray<NSDictionary *> *valid=[NSMutableArray new];NSError *error=nil;
        for(NSURL *root in roots){KVSoundPack *pack=loadPack(root,&error);if(pack)[valid addObject:@{@"root":root,@"pack":pack}];}
        if(!valid.count){NSAlert *alert=[NSAlert new];alert.messageText=@"No se ha encontrado ningún pack válido";alert.informativeText=error.localizedDescription?:@"La carpeta necesita un pack.json y sus archivos WAV o AIFF.";[alert runModal];return;}
        NSURL *destination=[self packsDirectory];
        [NSFileManager.defaultManager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:&error];
        NSUInteger copied=0;
        for(NSDictionary *item in valid){
            NSURL *root=item[@"root"];NSString *stem=root.lastPathComponent;NSURL *target=[destination URLByAppendingPathComponent:stem isDirectory:YES];unsigned suffix=2;
            while([NSFileManager.defaultManager fileExistsAtPath:target.path])target=[destination URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%u)",stem,suffix++] isDirectory:YES];
            if([NSFileManager.defaultManager copyItemAtURL:root toURL:target error:&error])copied++;
        }
        if(!copied){NSAlert *alert=[NSAlert new];alert.messageText=@"No se ha podido copiar el pack";alert.informativeText=error.localizedDescription?:@"Comprueba los permisos de la carpeta.";[alert runModal];return;}
        KVSoundPack *lastPack=valid.lastObject[@"pack"];
        [NSUserDefaults.standardUserDefaults setObject:lastPack.name forKey:@"selectedPackName"];
        [self restorePacks];[self save:nil];[self preview:nil];
        self.levelLabel.stringValue=[NSString stringWithFormat:@"%lu %@ importado%@",copied,copied==1?@"pack":@"packs",copied==1?@"":@"s"];
    }];
}
- (void)preview:(id)sender {[self playForce:.6 group:0 packGroup:@"alpha"];}
- (void)refresh:(id)sender {
    double now=nowSeconds();BOOL live=sampleCount && now-sampleTimes[(sampleCount-1)%2048]<.25;
    self.meter.doubleValue=live?fmin(1,peakBetween(now-.08,now)*self.sensitivity.doubleValue/.025):0;
    self.sensorLabel.stringValue=live?[NSString stringWithFormat:@"Acelerómetro activo · %lu muestras recibidas",sampleCount]:self.sensorStatus;
    if(sensorDevice&&!live)self.sensorLabel.stringValue=@"Sensor abierto, sin datos recientes";
    if(!self.tap && CGPreflightListenEventAccess())[self connectKeyboard];
    self.keyboardLabel.stringValue=self.tap?@"Teclado conectado · sin registrar texto":@"Activa KeyVibe en Privacidad → Monitorización de entrada";
}
- (void)save:(id)sender {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;[d setDouble:self.volume.doubleValue forKey:@"volume"];[d setDouble:self.sensitivity.doubleValue forKey:@"sensitivity"];[d setInteger:self.style.indexOfSelectedItem forKey:@"style"];[d setBool:self.enabled.state==NSControlStateValueOn forKey:@"enabled"];
    NSInteger imported=self.style.indexOfSelectedItem-(NSInteger)styleNames().count;
    if(imported>=0 && imported<(NSInteger)self.importedNames.count)[d setObject:self.importedNames[imported] forKey:@"importedSound"];
    else [d removeObjectForKey:@"importedSound"];
    NSInteger pack=imported-(NSInteger)self.importedNames.count;
    if(pack>=0 && pack<(NSInteger)self.packs.count)[d setObject:self.packs[pack].name forKey:@"selectedPackName"];
    else [d removeObjectForKey:@"selectedPackName"];
    if(self.enabled.state!=NSControlStateValueOn)for(AVAudioPlayerNode *p in self.voices){[p stop];[p play];}
    NSString *symbol=self.enabled.state==NSControlStateValueOn?@"keyboard":@"pause.circle";
    self.statusItem.button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"KeyVibe"];
    self.statusItem.button.image.template=YES;
}
- (void)wake:(NSNotification *)note {stopSensor();self.sensorStatus=startSensor();}
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.timer invalidate];stopSensor();[self.engine stop];if(self.tapSource){CFRunLoopRemoveSource(CFRunLoopGetMain(),self.tapSource,kCFRunLoopCommonModes);CFRelease(self.tapSource);}if(self.tap){CFMachPortInvalidate(self.tap);CFRelease(self.tap);}
}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc>1 && !strcmp(argv[1],"--permission-check")) {
            BOOL allowed=CGPreflightListenEventAccess();
            puts(allowed?"PERMISO_TECLADO_OK":"PERMISO_TECLADO_PENDIENTE");
            return allowed?0:3;
        }
        if(argc>1 && !strcmp(argv[1],"--self-test")) {
            AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
            for(int s=0;s<(int)styleNames().count;s++)for(int t=0;t<3;t++)for(int g=0;g<3;g++)for(int v=0;v<3;v++){
                AVAudioPCMBuffer *b=makeClick(format,s,t,g,v);double energy=0;
                for(unsigned i=0;i<b.frameLength;i++){float x=b.floatChannelData[0][i];if(!isfinite(x)||fabs(x)>.96)return 1;energy+=x*x;}
                if(energy<.001 || b.frameLength!=4080)return 2;
            }
            sampleCount=3;sampleTimes[0]=1;sampleTimes[1]=2;sampleTimes[2]=3;impacts[0]=.2;impacts[1]=.8;impacts[2]=.1;
            if(fabs(peakBetween(1.5,2.5)-.8)>1e-6 || peakBetween(4,5)!=0)return 3;
            printf("OK: %lu sonidos válidos sin clipping; selección temporal del impacto.\n",styleNames().count*27);return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        KeyVibe *delegate=[KeyVibe new];app.delegate=delegate;[app run];
    }return 0;
}
