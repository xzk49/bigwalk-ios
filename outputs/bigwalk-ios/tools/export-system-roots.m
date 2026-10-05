#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Export only macOS's read-only system root keychain, never user/admin stores.
// The iOS adapter must independently accept each certificate via SecTrust.
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        SecKeychainRef keychain = NULL;
        OSStatus status = SecKeychainOpen("/System/Library/Keychains/SystemRootCertificates.keychain", &keychain);
        CFTypeRef certificates = NULL;
        if (status == errSecSuccess && keychain) {
            NSDictionary *query = @{(__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassCertificate,
                (__bridge NSString *)kSecMatchSearchList: @[(__bridge id)keychain],
                (__bridge NSString *)kSecMatchLimit: (__bridge NSString *)kSecMatchLimitAll,
                (__bridge NSString *)kSecReturnRef: @YES};
            status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &certificates);
        }
        if (keychain) CFRelease(keychain);
        if (status != errSecSuccess || !certificates || CFGetTypeID(certificates) != CFArrayGetTypeID()) {
            fprintf(stderr, "System certificate enumeration failed: %d\n", (int)status);
            return 1;
        }
        NSMutableArray *records = [NSMutableArray new];
        NSArray *keys = @[(__bridge NSString *)kSecOIDX509V1IssuerName,
                          (__bridge NSString *)kSecOIDX509V1SubjectName];
        for (id value in (__bridge NSArray *)certificates) {
            SecCertificateRef certificate = (__bridge SecCertificateRef)value;
            CFDataRef der = SecCertificateCopyData(certificate);
            CFErrorRef error = NULL;
            CFDictionaryRef properties = SecCertificateCopyValues(certificate, (__bridge CFArrayRef)keys, &error);
            if (der && properties && !error) {
                [records addObject:@{@"der": (__bridge NSData *)der,
                                     @"properties": (__bridge NSDictionary *)properties}];
            }
            if (error) CFRelease(error);
            if (properties) CFRelease(properties);
            if (der) CFRelease(der);
        }
        CFRelease(certificates);
        NSDictionary *manifest = @{@"domain": @"macOS read-only SystemRootCertificates.keychain",
                                   @"issuerKey": keys[0], @"subjectKey": keys[1],
                                   @"records": records};
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        if (!data || ![data writeToFile:[NSString stringWithUTF8String:argv[1]] options:NSDataWritingAtomic error:&error]) {
            fprintf(stderr, "Export write failed: %s\n", error.description.UTF8String);
            return 1;
        }
        printf("%lu system certificates; issuer=%s subject=%s\n", (unsigned long)records.count,
               [keys[0] UTF8String], [keys[1] UTF8String]);
        return records.count ? 0 : 1;
    }
}
