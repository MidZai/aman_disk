#include "CDiskIO.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOMedia.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/ata/ATASMARTLib.h>
#include <string.h>
#include <stdio.h>

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
    
    io_object_t smart_service = 0;
    
    while (current != 0) {
        CFTypeRef smart_cap = IORegistryEntrySearchCFProperty(current, kIOServicePlane, CFSTR("SMART Capable"), kCFAllocatorDefault, 0);
        if (smart_cap) {
            if (CFGetTypeID(smart_cap) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)smart_cap)) {
                smart_service = current;
                IOObjectRetain(smart_service);
                CFRelease(smart_cap);
                break;
            }
            CFRelease(smart_cap);
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
    
    if (smart_service == 0) {
        return -4;
    }
    
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kr = IOCreatePlugInInterfaceForService(smart_service, kIOATASMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(smart_service);
    
    if (kr != kIOReturnSuccess || !plugin) {
        return -5;
    }
    
    IOATASMARTInterface **smart_interface = NULL;
    HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID), (LPVOID *)&smart_interface);
    if (res != S_OK || !smart_interface) {
        IODestroyPlugInInterface(plugin);
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
        if (kr == kIOReturnNotPermitted || kr == kIOReturnNoDevice) { // Or other error for disabled SMART
            IODestroyPlugInInterface(plugin);
            return -6;
        }
        IODestroyPlugInInterface(plugin);
        return -5;
    }
    
    kr = (*smart_interface)->SMARTValidateReadData(smart_interface, (const ATASMARTData *)out);
    if (kr != kIOReturnSuccess) {
        fprintf(stderr, "Warning: SMARTValidateReadData failed\n");
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
        IODestroyPlugInInterface(plugin);
        return -6; // or -5, returning -6 just in case SMART is disabled
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
        IODestroyPlugInInterface(plugin);
        return -6;
    }
    
    if (threshold_exceeded) {
        *threshold_exceeded = exceeded ? 1 : 0;
    }
    
    IODestroyPlugInInterface(plugin);
    return 0;
}
