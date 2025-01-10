#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>
@import Foundation;
@import Darwin;
@import MachO;

void loadMobileGestaltFileFromUser() {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setAllowedFileTypes:@[@"plist"]];

    if ([openPanel runModal] == NSModalResponseOK) {
        NSURL *selectedFileURL = [openPanel URL];
        if (selectedFileURL) {
            NSError *error = nil;
            NSData *fileData = [NSData dataWithContentsOfURL:selectedFileURL options:0 error:&error];
            if (fileData) {
                NSString *filePath = [selectedFileURL path];
                [NSUserDefaults.standardUserDefaults setObject:filePath forKey:@"MobileGestaltFilePath"];
            } else {
                NSLog(@"Failed to load MobileGestalt file: %@", error);
            }
        }
    }
}

__attribute__((constructor)) void FindCacheDataOffset() {
    NSString *mobileGestaltFilePath = [NSUserDefaults.standardUserDefaults stringForKey:@"MobileGestaltFilePath"];
    if (!mobileGestaltFilePath) {
        loadMobileGestaltFileFromUser();
        mobileGestaltFilePath = [NSUserDefaults.standardUserDefaults stringForKey:@"MobileGestaltFilePath"];
    }

    if (!mobileGestaltFilePath) {
        NSLog(@"MobileGestalt file not loaded. Exiting.");
        return;
    }

    const struct mach_header_64 *header = NULL;
    const char *mgName = [mobileGestaltFilePath UTF8String];
    const char *mgKey = "mtrAoWJ3gsq+I90ZnQ0vQw";
    dlopen(mgName, RTLD_GLOBAL);

    for (int i = 0; i < _dyld_image_count(); i++) {
        if (!strncmp(mgName, _dyld_get_image_name(i), strlen(mgName))) {
            header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            break;
        }
    }
    assert(header);

    // Get a pointer to the corresponding obfuscated key in libMobileGestalt
    size_t textCStringSize;
    const char *textCStringSection = (const char *)getsectiondata(header, "__TEXT", "__cstring", &textCStringSize);
    for (size_t size = 0; size < textCStringSize; size += strlen(textCStringSection + size) + 1) {
        if (!strncmp(mgKey, textCStringSection + size, strlen(mgKey))) {
            textCStringSection += size;
            break;
        }
    }

    // Get a pointer to an unknown struct, whose first pointer is the pointer to the obfuscated key
    size_t constSize;
    // arm64e
    const uintptr_t *constSection = (const uintptr_t *)getsectiondata(header, "__AUTH_CONST", "__const", &constSize);
    if (!constSection) {
        // arm64, FIXME: is this correct?
        constSection = (const uintptr_t *)getsectiondata(header, "__DATA_CONST", "__const", &constSize);
    }
    for (int i = 0; i < constSize / 8; i++) {
        if (constSection[i] == (uintptr_t)textCStringSection) {
            constSection += i;
            break;
        }
    }

    // FIXME: is offset of offset consistent?
    off_t offset = (off_t)((uint16_t *)constSection)[0x9a/2] << 3;
    [NSUserDefaults.standardUserDefaults setInteger:offset forKey:@"MGCacheDataDeviceClassNumberOffset"];
}
