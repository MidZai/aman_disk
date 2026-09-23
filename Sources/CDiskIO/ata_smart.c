#include "CDiskIO.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/ata/ATASMARTLib.h>
#include <string.h>
#include <stdio.h>

static int is_smart_disabled(IOATASMARTInterface **smart_interface) {
    if (!smart_interface) return 0;
    unsigned char identify[512] = {0};
    UInt32 outSize = 0;
    IOReturn ikr = (*smart_interface)->GetATAIdentifyData(smart_interface, identify, 512, &outSize);
    if (ikr == kIOReturnSuccess && outSize >= 512) {
        unsigned short *words = (unsigned short *)identify;
        // Word 82 bit 0 = SMART feature set supported
        // Word 85 bit 0 = SMART feature set enabled
        if ((words[82] & 0x0001) != 0 && (words[85] & 0x0001) == 0) {
            return 1;
        }
    }
    return 0;
}

static int get_ata_smart_interface(const char *bsd_name, IOCFPlugInInterface ***out_plugin, IOATASMARTInterface ***out_smart_interface) {
    if (!bsd_name || !out_plugin || !out_smart_interface) return -1;
    
    CFDictionaryRef matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsd_name);
    if (!matching) {
        return -2;
    }
    
    io_iterator_t iterator = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (kr != kIOReturnSuccess || iterator == 0) {
        return -2;
    }
    
    io_object_t media = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    
    if (media == 0) {
        return -3;
    }
    
    io_object_t current = media;
    IOObjectRetain(current);
    
    IOCFPlugInInterface **plugin = NULL;
    IOATASMARTInterface **smart_interface = NULL;
    
    while (current != 0) {
        SInt32 score = 0;
        IOCFPlugInInterface **test_plugin = NULL;
        kr = IOCreatePlugInInterfaceForService(
            current,
            kIOATASMARTUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &test_plugin,
            &score
        );
        
        if (kr == kIOReturnSuccess && test_plugin != NULL) {
            IOATASMARTInterface **test_smart = NULL;
            HRESULT res = (*test_plugin)->QueryInterface(
                test_plugin,
                CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID),
                (LPVOID *)&test_smart
            );
            if (res == S_OK && test_smart != NULL) {
                plugin = test_plugin;
                smart_interface = test_smart;
                IOObjectRelease(current);
                break;
            }
            IODestroyPlugInInterface(test_plugin);
        }
        
        io_object_t parent = 0;
        kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        IOObjectRelease(current);
        if (kr == kIOReturnSuccess && parent != 0) {
            current = parent;
        } else {
            current = 0;
        }
    }
    
    IOObjectRelease(media);
    
    if (!plugin || !smart_interface) {
        return -5;
    }
    
    *out_plugin = plugin;
    *out_smart_interface = smart_interface;
    return 0;
}

int cdiskio_read_ata_smart_data(const char *bsd_name, unsigned char *out, int size) {
    if (size < 512) return -1;
    
    IOCFPlugInInterface **plugin = NULL;
    IOATASMARTInterface **smart_interface = NULL;
    
    int err = get_ata_smart_interface(bsd_name, &plugin, &smart_interface);
    if (err != 0) return err;
    
    IOReturn kr = (*smart_interface)->SMARTReadData(smart_interface, (ATASMARTData *)out);
    if (kr != kIOReturnSuccess) {
        if (kr == kIOReturnNotPermitted || kr == kIOReturnNoDevice || is_smart_disabled(smart_interface)) {
            IODestroyPlugInInterface(plugin);
            return -6;
        }
        IODestroyPlugInInterface(plugin);
        return -5;
    }
    
    kr = (*smart_interface)->SMARTValidateReadData(smart_interface, (const ATASMARTData *)out);
    if (kr != kIOReturnSuccess) {
        // Warning: checksum validation warning
    }
    
    IODestroyPlugInInterface(plugin);
    return 0;
}

int cdiskio_read_ata_smart_thresholds(const char *bsd_name, unsigned char *out, int size) {
    if (size < 512) return -1;
    
    IOCFPlugInInterface **plugin = NULL;
    IOATASMARTInterface **smart_interface = NULL;
    
    int err = get_ata_smart_interface(bsd_name, &plugin, &smart_interface);
    if (err != 0) return err;
    
    IOReturn kr = (*smart_interface)->SMARTReadDataThresholds(smart_interface, (ATASMARTDataThresholds *)out);
    if (kr != kIOReturnSuccess) {
        if (kr == kIOReturnNotPermitted || kr == kIOReturnNoDevice || is_smart_disabled(smart_interface)) {
            IODestroyPlugInInterface(plugin);
            return -6;
        }
        IODestroyPlugInInterface(plugin);
        return -5;
    }
    
    IODestroyPlugInInterface(plugin);
    return 0;
}

int cdiskio_read_ata_identify(const char *bsd_name, unsigned char *out, int size) {
    if (size < 512) return -1;
    
    IOCFPlugInInterface **plugin = NULL;
    IOATASMARTInterface **smart_interface = NULL;
    
    int err = get_ata_smart_interface(bsd_name, &plugin, &smart_interface);
    if (err != 0) return err;
    
    UInt32 outSize = 0;
    IOReturn kr = (*smart_interface)->GetATAIdentifyData(smart_interface, out, (UInt32)size, &outSize);
    if (kr != kIOReturnSuccess) {
        IODestroyPlugInInterface(plugin);
        return -5;
    }
    
    IODestroyPlugInInterface(plugin);
    return 0;
}

int cdiskio_read_ata_smart_status(const char *bsd_name, int *threshold_exceeded) {
    IOCFPlugInInterface **plugin = NULL;
    IOATASMARTInterface **smart_interface = NULL;
    
    int err = get_ata_smart_interface(bsd_name, &plugin, &smart_interface);
    if (err != 0) return err;
    
    Boolean exceeded = false;
    IOReturn kr = (*smart_interface)->SMARTReturnStatus(smart_interface, &exceeded);
    if (kr != kIOReturnSuccess) {
        if (kr == kIOReturnNotPermitted || kr == kIOReturnNoDevice || is_smart_disabled(smart_interface)) {
            IODestroyPlugInInterface(plugin);
            return -6;
        }
        IODestroyPlugInInterface(plugin);
        return -5;
    }
    
    if (threshold_exceeded) {
        *threshold_exceeded = exceeded ? 1 : 0;
    }
    
    IODestroyPlugInInterface(plugin);
    return 0;
}
