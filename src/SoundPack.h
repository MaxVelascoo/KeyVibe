#import <AVFoundation/AVFoundation.h>

@interface KVSoundPack : NSObject
@property NSString *name;
@property NSString *author;
@property NSString *licenseName;
@property NSString *identifier;
@property NSDictionary<NSString *,NSArray<AVAudioPCMBuffer *> *> *groups;
@property NSDictionary<NSString *,NSArray<AVAudioPCMBuffer *> *> *releaseGroups;
@property NSUInteger fileCount;
@end
@implementation KVSoundPack
@end

static NSString *packMapKey(NSString *group, NSString *tier) {
    return [NSString stringWithFormat:@"%@/%@",group,tier];
}

static NSURL *safePackFile(NSURL *root, NSString *relative) {
    if(![relative isKindOfClass:NSString.class] || !relative.length || relative.isAbsolutePath)return nil;
    NSURL *resolved=[[root URLByAppendingPathComponent:relative] URLByResolvingSymlinksInPath].standardizedURL;
    NSString *prefix=[root.URLByResolvingSymlinksInPath.standardizedURL.path stringByAppendingString:@"/"];
    return [resolved.path hasPrefix:prefix]?resolved:nil;
}

static KVSoundPack *loadPack(NSURL *root, NSError **outError) {
    NSURL *manifest=[root URLByAppendingPathComponent:@"pack.json"];
    NSData *data=[NSData dataWithContentsOfURL:manifest options:NSDataReadingMappedIfSafe error:outError];
    if(!data || data.length>1024*1024){
        if(data && outError)*outError=soundError(@"El pack.json supera 1 MB.");
        return nil;
    }
    id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    if(![object isKindOfClass:NSDictionary.class]){if(object&&outError)*outError=soundError(@"pack.json no contiene un objeto JSON.");return nil;}
    NSDictionary *json=object;
    if(![json[@"name"] isKindOfClass:NSString.class] || ![json[@"groups"] isKindOfClass:NSDictionary.class]){
        if(outError)*outError=soundError(@"El pack necesita los campos name y groups.");return nil;
    }
    NSMutableDictionary *cache=[NSMutableDictionary new],*groups=[NSMutableDictionary new],*releases=[NSMutableDictionary new];
    __block NSError *error=nil;__block NSUInteger references=0;
    AVAudioPCMBuffer *(^decode)(NSString *)=^AVAudioPCMBuffer *(NSString *relative){
        if(++references>1000){error=soundError(@"El pack contiene demasiadas referencias.");return nil;}
        NSURL *url=safePackFile(root,relative);if(!url){error=soundError(@"El pack contiene una ruta de audio no válida.");return nil;}
        AVAudioPCMBuffer *buffer=cache[url.path];
        if(!buffer){buffer=loadSoundWithLimit(url,2,&error);if(buffer)cache[url.path]=buffer;}
        return buffer;
    };
    NSDictionary *groupJSON=json[@"groups"];
    for(NSString *group in groupJSON){
        if(![group isKindOfClass:NSString.class] || ![groupJSON[group] isKindOfClass:NSDictionary.class])continue;
        for(NSString *tier in groupJSON[group]){
            id paths=groupJSON[group][tier];if(![paths isKindOfClass:NSArray.class])continue;
            NSMutableArray *buffers=[NSMutableArray new];
            for(id path in paths){if(![path isKindOfClass:NSString.class])continue;AVAudioPCMBuffer *b=decode(path);if(!b){if(outError)*outError=error;return nil;}[buffers addObject:b];}
            if(buffers.count)groups[packMapKey(group,tier)]=buffers;
        }
    }
    if(!groups.count){if(outError)*outError=error?:soundError(@"El pack no contiene sonidos reproducibles.");return nil;}
    if([json[@"release"] isKindOfClass:NSDictionary.class])for(NSString *group in json[@"release"]){
        id paths=json[@"release"][group];if(![paths isKindOfClass:NSArray.class])continue;
        NSMutableArray *buffers=[NSMutableArray new];
        for(id path in paths){if(![path isKindOfClass:NSString.class])continue;AVAudioPCMBuffer *b=decode(path);if(!b){if(outError)*outError=error;return nil;}[buffers addObject:b];}
        if(buffers.count)releases[group]=buffers;
    }
    KVSoundPack *pack=[KVSoundPack new];pack.name=json[@"name"];
    pack.author=[json[@"author"] isKindOfClass:NSString.class]?json[@"author"]:@"Autor desconocido";
    pack.licenseName=[json[@"license"] isKindOfClass:NSString.class]?json[@"license"]:@"Licencia no indicada";
    pack.identifier=[NSString stringWithFormat:@"%@|%@",root.path,pack.name];pack.groups=groups;pack.releaseGroups=releases;pack.fileCount=cache.count;
    return pack;
}

static NSArray<AVAudioPCMBuffer *> *packBuffers(KVSoundPack *pack, NSString *group, NSString *tier) {
    NSArray *result=pack.groups[packMapKey(group,tier)];
    if(!result)result=pack.groups[packMapKey(@"other",tier)];
    if(!result)result=pack.groups[packMapKey(@"alpha",tier)];
    return result;
}

static NSArray<AVAudioPCMBuffer *> *packReleaseBuffers(KVSoundPack *pack, NSString *group) {
    NSArray *result=pack.releaseGroups[group];
    if(!result)result=pack.releaseGroups[@"other"];
    if(!result)result=pack.releaseGroups[@"alpha"];
    return result;
}
