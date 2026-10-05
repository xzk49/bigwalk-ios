#import <Security/Security.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdint.h>

const CFStringRef BigWalkIssuerName __asm__("_kSecOIDX509V1IssuerName") = CFSTR("2.16.840.1.113741.2.1.1.1.5");
const CFStringRef BigWalkSubjectName __asm__("_kSecOIDX509V1SubjectName") = CFSTR("2.16.840.1.113741.2.1.1.1.8");

static NSArray *acceptedRoots;
static NSDictionary<NSData *, NSDictionary *> *acceptedProperties;

static void LoadAcceptedSystemRoots(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *roots = [NSMutableArray new];
        NSMutableDictionary *properties = [NSMutableDictionary new];
        if (![NSBundle.mainBundle.infoDictionary[@"BigWalkIOSSystemRoots"] boolValue]) {
            acceptedRoots = @[]; acceptedProperties = @{}; return;
        }
        NSString *path = [NSBundle.mainBundle pathForResource:@"SystemRootCandidates" ofType:@"plist"];
        NSDictionary *manifest = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        NSArray *records = manifest[@"records"];
        BOOL validManifest = [manifest[@"domain"] isEqual:@"macOS read-only SystemRootCertificates.keychain"] &&
            [manifest[@"issuerKey"] isEqual:(__bridge NSString *)BigWalkIssuerName] &&
            [manifest[@"subjectKey"] isEqual:(__bridge NSString *)BigWalkSubjectName] &&
            [records isKindOfClass:NSArray.class];
        if (!validManifest) records = @[];
        NSUInteger rejected = 0;
        for (NSDictionary *record in records) {
            NSData *der = record[@"der"];
            NSDictionary *values = record[@"properties"];
            if (![der isKindOfClass:NSData.class] || ![values isKindOfClass:NSDictionary.class]) { rejected++; continue; }
            SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der);
            SecPolicyRef policy = SecPolicyCreateBasicX509();
            SecTrustRef trust = NULL;
            OSStatus status = certificate && policy ? SecTrustCreateWithCertificates(certificate, policy, &trust) : errSecParam;
            if (trust) SecTrustSetNetworkFetchAllowed(trust, false);
            CFErrorRef error = NULL;
            // No custom anchors or trust overrides: only roots already trusted
            // by this iOS device can enter the original Unity CA collection.
            BOOL trusted = status == errSecSuccess && trust && SecTrustEvaluateWithError(trust, &error);
            if (trusted) {
                [roots addObject:(__bridge id)certificate];
                properties[der] = values;
            } else rejected++;
            if (error) CFRelease(error);
            if (trust) CFRelease(trust);
            if (policy) CFRelease(policy);
            if (certificate) CFRelease(certificate);
        }
        acceptedRoots = [roots copy]; acceptedProperties = [properties copy];
        fprintf(stderr, "BIGWALK_TLS native_root_validation candidates=%lu accepted=%lu rejected=%lu custom_anchors=0\n",
            (unsigned long)records.count, (unsigned long)roots.count, (unsigned long)rejected);
    });
}

// iOS has no macOS user/admin Trust Settings domains. The optional system
// collection is limited to bundled public roots accepted by native SecTrust.
OSStatus SecTrustSettingsCopyCertificates(uint32_t domain, CFArrayRef *certificates) {
    if (!certificates) return errSecParam;
    *certificates = NULL;
    if (domain > 2) return errSecParam;
    if (domain == 2) {
        LoadAcceptedSystemRoots();
        if (acceptedRoots.count) {
            *certificates = CFBridgingRetain(acceptedRoots);
            return errSecSuccess;
        }
    }
    fprintf(stderr, "BIGWALK_TLS mac_trust_settings_domain=%u certificates=0 status=%d\n",
            domain, (int)errSecNoTrustSettings);
    return errSecNoTrustSettings;
}

OSStatus SecTrustSettingsCopyTrustSettings(SecCertificateRef certificate, uint32_t domain,
                                         CFArrayRef *settings) {
    if (!settings) return errSecParam;
    *settings = NULL;
    if (!certificate || domain > 2) return errSecParam;
    return errSecItemNotFound;
}

CFDictionaryRef BigWalkCopyCertificateValues(SecCertificateRef certificate, CFArrayRef keys,
                                             CFErrorRef *error) __asm__("_SecCertificateCopyValues");
CFDictionaryRef BigWalkCopyCertificateValues(SecCertificateRef certificate, CFArrayRef keys,
                                             CFErrorRef *error) {
    if (error) *error = NULL;
    LoadAcceptedSystemRoots();
    NSData *der = certificate ? CFBridgingRelease(SecCertificateCopyData(certificate)) : nil;
    NSDictionary *values = der ? acceptedProperties[der] : nil;
    NSMutableDictionary *result = [NSMutableDictionary new];
    BOOL supported = values != nil;
    if (supported && keys) {
        for (id key in (__bridge NSArray *)keys) {
            id value = values[key];
            if (!value) { supported = NO; break; }
            result[key] = value;
        }
    } else if (supported) [result addEntriesFromDictionary:values];
    if (!supported) {
        if (error) *error = CFErrorCreate(NULL, kCFErrorDomainOSStatus, errSecItemNotFound, NULL);
        return NULL;
    }
    // Preserve the actual macOS property structure exported for this DER;
    // Unity compares issuer/subject values while selecting self-signed roots.
    return CFBridgingRetain(result);
}
