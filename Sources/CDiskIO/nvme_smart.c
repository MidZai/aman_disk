#include "CDiskIO.h"
#include "nvme_interface.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <stdio.h>
#include <string.h>

static int _cdiskio_do_nvme_operation(const char *bsd_name, unsigned char *out_buffer, int buffer_size, int op_type) {
    // op_type: 1 = SMART, 2 = Identify
    if ((op_type == 1 && buffer_size < 512) || (op_type == 2 && buffer_size < 4096)) {
        return -5;
    }

    io_service_t service = MACH_PORT_NULL;
    io_service_t target_service = MACH_PORT_NULL;
    IOCFPlugInInterface **plugin = NULL;
    IONVMeSMARTInterface **smartIf = NULL;
    int result = -1;
    SInt32 score = 0;
    IOReturn err = kIOReturnSuccess;

    // 1. Get IOMedia service from bsd_name
    CFMutableDictionaryRef matchingDict = IOBSDNameMatching(kIOMainPortDefault, 0, bsd_name);
    if (!matchingDict) {
        return -1;
    }

    service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict);
    if (service == MACH_PORT_NULL) {
        return -1;
    }

    // 2. Traverse parents in kIOServicePlane to find NVMe SMART Capable
    io_iterator_t iter;
    err = IORegistryEntryCreateIterator(service, kIOServicePlane, kIORegistryIterateRecursively | kIORegistryIterateParents, &iter);
    if (err != kIOReturnSuccess) {
        result = -2;
        goto cleanup;
    }

    target_service = service;
    IOObjectRetain(target_service);

    bool found = false;
    while (target_service != MACH_PORT_NULL) {
        CFTypeRef smartCapable = IORegistryEntryCreateCFProperty(target_service, CFSTR("NVMe SMART Capable"), kCFAllocatorDefault, 0);
        if (smartCapable) {
            if (CFGetTypeID(smartCapable) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)smartCapable)) {
                found = true;
                CFRelease(smartCapable);
                break;
            }
            CFRelease(smartCapable);
        }
        
        io_service_t parent = MACH_PORT_NULL;
        IORegistryEntryGetParentEntry(target_service, kIOServicePlane, &parent);
        IOObjectRelease(target_service);
        target_service = parent;
    }
    IOObjectRelease(iter);

    if (!found || target_service == MACH_PORT_NULL) {
        result = -2;
        goto cleanup;
    }

    // 3. IOCreatePlugInInterfaceForService
    err = IOCreatePlugInInterfaceForService(target_service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (err != kIOReturnSuccess || !plugin) {
        fprintf(stderr, "IOCreatePlugInInterfaceForService failed: 0x%08x\n", err);
        result = -3;
        goto cleanup;
    }

    // 4. QueryInterface
    err = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smartIf);
    if (err != kIOReturnSuccess || !smartIf) {
        fprintf(stderr, "QueryInterface failed: 0x%08x\n", err);
        result = -3;
        goto cleanup;
    }

    // 5. Read data
    memset(out_buffer, 0, buffer_size);
    if (op_type == 1) {
        err = (*smartIf)->SMARTReadData(smartIf, out_buffer);
        if (err != kIOReturnSuccess) {
            fprintf(stderr, "SMARTReadData failed: 0x%08x\n", err);
            result = -4;
        } else {
            result = 0;
        }
    } else if (op_type == 2) {
        err = (*smartIf)->GetIdentifyData(smartIf, out_buffer, 0); // namespace 0 implies controller for Apple's interface?
        if (err != kIOReturnSuccess) {
            fprintf(stderr, "GetIdentifyData failed: 0x%08x\n", err);
            result = -4;
        } else {
            result = 0;
        }
    }

cleanup:
    // 6. Cleanup
    if (smartIf) {
        (*smartIf)->Release(smartIf);
    }
    if (plugin) {
        IODestroyPlugInInterface(plugin);
    }
    if (target_service != MACH_PORT_NULL) {
        IOObjectRelease(target_service);
    }
    if (service != MACH_PORT_NULL) {
        IOObjectRelease(service);
    }

    return result;
}


int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size) {
    return _cdiskio_do_nvme_operation(bsd_name, out_buffer, buffer_size, 1);
}

int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size) {
    return _cdiskio_do_nvme_operation(bsd_name, out_buffer, buffer_size, 2);
}
