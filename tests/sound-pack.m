#import "../src/ImportedSound.h"
#import "../src/SoundPack.h"

int main(int argc,const char **argv){@autoreleasepool{
    NSString *path=argc>1?[NSString stringWithUTF8String:argv[1]]:@"/Applications/Haptyk.app/Contents/Resources/SoundPacks";
    NSArray *roots=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:path isDirectory:YES] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSUInteger packs=0,files=0,missing=0;
    for(NSURL *root in roots){
        if(![[NSFileManager defaultManager] fileExistsAtPath:[root URLByAppendingPathComponent:@"pack.json"].path])continue;
        NSError *error=nil;KVSoundPack *pack=loadPack(root,&error);
        if(!pack){fprintf(stderr,"FAILED %s: %s\n",root.lastPathComponent.UTF8String,error.localizedDescription.UTF8String);return 1;}
        packs++;files+=pack.fileCount;
        for(NSString *tier in @[@"soft",@"medium",@"hard",@"slam"])if(!packBuffers(pack,@"alpha",tier).count)missing++;
        if(!pack.name.length || !pack.author.length || !pack.licenseName.length)return 2;
    }
    if(packs!=16 || files!=680 || missing)return 3;
    NSURL *root=[NSURL fileURLWithPath:@"/tmp/keyvibe-pack-root" isDirectory:YES];
    if(safePackFile(root,@"../escape.wav") || safePackFile(root,@"/tmp/escape.wav"))return 4;
    printf("OK: %lu packs, %lu WAV únicos, 4 intensidades y rutas confinadas.\n",packs,files);
    return 0;
}}
