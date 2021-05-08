//
//  main.m
//  K0syi
//
//  Created by Tamas Lustyik on 2021. 05. 01..
//

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

@interface K0syiTransformer: NSObject
@end

@implementation K0syiTransformer

- (void)handleServiceRequestWithPBoard:(NSPasteboard*)pboard userData:(NSString*)data error:(NSString**)errorStr {
    if (![pboard canReadObjectForClasses:@[[NSString class]] options:nil]) {
        *errorStr = @"no string found on pboard";
        return;

    }
    NSString* srcString = [pboard stringForType:NSPasteboardTypeString];
    if (!srcString) {
        *errorStr = @"pboard string is nil";
        return;
    }

    NSDictionary* props = @{
        (__bridge NSString*)kTISPropertyInputSourceCategory: (__bridge NSString*)kTISCategoryKeyboardInputSource,
        (__bridge NSString*)kTISPropertyInputSourceType: (__bridge NSString*)kTISTypeKeyboardLayout,
        (__bridge NSString*)kTISPropertyInputSourceIsSelected: @NO
    };
    NSArray* sources = (__bridge NSArray*)TISCreateInputSourceList((__bridge CFDictionaryRef)props, false);

    if (sources.count != 1) {
        *errorStr = @"cannot detect alternate keyboard layout";
        return;
    }

    TISInputSourceRef otherSource = (__bridge TISInputSourceRef)sources.firstObject;
    NSData* otherLayoutData = (__bridge NSData*)TISGetInputSourceProperty(otherSource, kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout* otherLayout = (const UCKeyboardLayout*)otherLayoutData.bytes;

    TISInputSourceRef currentSource = TISCopyCurrentKeyboardLayoutInputSource();
    NSData* currentLayoutData = (__bridge NSData*)TISGetInputSourceProperty(currentSource, kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout* currentLayout = (const UCKeyboardLayout*)currentLayoutData.bytes;

    NSData* utf32Data = [srcString dataUsingEncoding:NSUTF32LittleEndianStringEncoding];

    NSMutableDictionary* gcMap = [NSMutableDictionary dictionary];
    NSMutableString* dstString = [NSMutableString stringWithCapacity:srcString.length];
    UInt32 keyboardType = LMGetKbdType();

    for (NSUInteger i = 0; i < utf32Data.length; i+=4) {
        NSString* graphemeCluster = [[NSString alloc] initWithData:[utf32Data subdataWithRange:NSMakeRange(i, 4)]
                                                          encoding:NSUTF32LittleEndianStringEncoding];
        if (gcMap[graphemeCluster]) {
            [dstString appendString:gcMap[graphemeCluster]];
            continue;
        }

        // reverse lookup (unichar in current layout --> virtual key)
        UInt32 deadKeyState = 0;
        UniChar buffer[64];
        UniCharCount charCount = 0;
        UInt16 vk = 0;
        UInt32 modifiers = 0;
        for (; vk <= 0xff; ++vk) {
            if ([self isKeypadVirtualKeyCode:vk]) {
                continue;
            }
            if (!UCKeyTranslate(currentLayout, vk, kUCKeyActionDown, modifiers, keyboardType, kUCKeyTranslateNoDeadKeysBit, &deadKeyState, 64, &charCount, buffer) &&
                [[NSString stringWithCharacters:buffer length:charCount] isEqualToString:graphemeCluster]) {
                break;
            }
        }
        if (vk > 0xff) {
            modifiers = shiftKey >> 8;
            for (vk = 0; vk <= 0xff; ++vk) {
                if ([self isKeypadVirtualKeyCode:vk]) {
                    continue;
                }
                if (!UCKeyTranslate(currentLayout, vk, kUCKeyActionDown, modifiers, keyboardType, kUCKeyTranslateNoDeadKeysBit, &deadKeyState, 64, &charCount, buffer) &&
                    [[NSString stringWithCharacters:buffer length:charCount] isEqualToString:graphemeCluster]) {
                    break;
                }
            }
        }

        // forward lookup (virtual key --> unichar in other layout)
        if (vk <= 0xff && !UCKeyTranslate(otherLayout, vk, kUCKeyActionDown, modifiers, LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit, &deadKeyState, 64, &charCount, buffer)) {
            gcMap[graphemeCluster] = [NSString stringWithCharacters:buffer length:charCount];
            [dstString appendString:gcMap[graphemeCluster]];
        } else {
            // no virtual key found, copy as-is
            [dstString appendString:graphemeCluster];
        }
    }

    CFRelease(currentSource);

    [pboard clearContents];
    [pboard writeObjects:[NSArray arrayWithObject:dstString]];
}

- (BOOL)isKeypadVirtualKeyCode:(UInt16)vk {
    switch (vk) {
        case kVK_ANSI_KeypadClear:
        case kVK_ANSI_KeypadEquals:
        case kVK_ANSI_KeypadMultiply:
        case kVK_ANSI_KeypadDivide:
        case kVK_ANSI_KeypadMinus:
        case kVK_ANSI_KeypadPlus:
        case kVK_ANSI_KeypadEnter:
        case kVK_ANSI_KeypadDecimal:
        case kVK_ANSI_Keypad0:
        case kVK_ANSI_Keypad1:
        case kVK_ANSI_Keypad2:
        case kVK_ANSI_Keypad3:
        case kVK_ANSI_Keypad4:
        case kVK_ANSI_Keypad5:
        case kVK_ANSI_Keypad6:
        case kVK_ANSI_Keypad7:
        case kVK_ANSI_Keypad8:
        case kVK_ANSI_Keypad9:
            return YES;
    }
    return NO;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        id transformer = [K0syiTransformer new];
        [NSApplication sharedApplication].servicesProvider = transformer;
        [[NSApplication sharedApplication] run];
    }
    return 0;
}
