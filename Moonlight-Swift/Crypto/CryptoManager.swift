//
//  CryptoManager.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 09.03.2026.
//

import Foundation
import OpenSSL

class CryptoManager {
    private static var key: Data?
    private static var cert: Data?
    private static var p12: Data?
}

// MARK: - Static access
extension CryptoManager {
    static func generateKeyPairUsingSSL() {
        guard !CryptoManager.keyPairExists() else { return }

        Log.i("Generating Certificate...")
        let certKeyPair = CryptoManager.generateCertKeyPair()

        writeCryptoObject("client.crt", data: certKeyPair.x509)
        writeCryptoObject("client.p12", data: certKeyPair.p12)
        writeCryptoObject("client.key", data: certKeyPair.pkey)

        Log.i("Certificate created")
    }

    static func readCertFromFile() -> Data {
        guard let cert else {
            let cert = Self.readCryptoObject("client.crt")!
            self.cert = cert
            return cert
        }
        return cert
    }

    static func readKeyFromFile() -> Data {
        guard let key else {
            let key = Self.readCryptoObject("client.key")!
            self.key = key
            return key
        }
        return key
    }

    static func readP12FromFile() -> Data {
        guard let p12 else {
            let p12 = Self.readCryptoObject("client.p12")!
            self.p12 = p12
            return p12
        }
        return p12
    }

    static func getSignatureFromCert(_ cert: Data) -> Data? {
        let x509: OpaquePointer? = cert.withUnsafeBytes { certBytes in
            guard let baseAddress = certBytes.baseAddress else { return nil }

            let bio = BIO_new_mem_buf(baseAddress, Int32(cert.count))
            defer {
                BIO_free(bio)
            }

            guard bio != nil else { return nil }
            return PEM_read_bio_X509(bio, nil, nil, nil)
        }

        guard let x509 else {
            Log.e("Unable to parse certificate in memory!")
            return nil
        }
        defer {
            X509_free(x509)
        }

        var asnSignature: UnsafePointer<ASN1_BIT_STRING>?
        X509_get0_signature(&asnSignature, nil, x509)

        guard let asnSignature else {
            return nil
        }

        guard let sigBytes = ASN1_STRING_get0_data(asnSignature) else {
            return nil
        }

        let sigLength = ASN1_STRING_length(asnSignature)
        guard sigLength > 0 else {
            return Data()
        }

        return Data(bytes: sigBytes, count: Int(sigLength))
    }

    static func pemToDer(_ pemCertBytes: Data) -> Data? {
        let x509: OpaquePointer? = pemCertBytes.withUnsafeBytes { pemBytes in
            guard let baseAddress = pemBytes.baseAddress else { return nil }

            let bio = BIO_new_mem_buf(baseAddress, Int32(pemCertBytes.count))
            defer { BIO_free(bio) }

            guard bio != nil else { return nil }
            return PEM_read_bio_X509(bio, nil, nil, nil)
        }

        guard let x509 else {
            Log.e("Unable to parse PEM certificate in memory!")
            return nil
        }
        defer { X509_free(x509) }

        let length = i2d_X509(x509, nil)
        guard length > 0 else {
            return nil
        }

        var der = Data(count: Int(length))

        let written = der.withUnsafeMutableBytes { derBytes -> Int32 in
            guard let base = derBytes.bindMemory(to: UInt8.self).baseAddress else {
                return -1
            }

            var out: UnsafeMutablePointer<UInt8>? = base
            return i2d_X509(x509, &out)
        }

        guard written == length else {
            return nil
        }

        return der
    }
}

// MARK: - Public access
extension CryptoManager {
    func createAESKeyFromSaltSHA1(_ saltedPIN: Data) -> Data {
        SHA1Hash(data: saltedPIN).subdata(in: 0 ..< 16)
    }

    func createAESKeyFromSaltSHA256(_ saltedPIN: Data) -> Data {
        SHA256Hash(data: saltedPIN).subdata(in: 0 ..< 16)
    }

    func SHA1Hash(data: Data) -> Data {
        var digest = Data(count: Int(SHA_DIGEST_LENGTH))

        digest.withUnsafeMutableBytes { digestBytes in
            data.withUnsafeBytes { dataBytes in
                _ = SHA1(
                    dataBytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    digestBytes.bindMemory(to: UInt8.self).baseAddress
                )
            }
        }

        return digest
    }

    func SHA256Hash(data: Data) -> Data {
        var digest = Data(count: Int(SHA256_DIGEST_LENGTH))

        digest.withUnsafeMutableBytes { digestBytes in
            data.withUnsafeBytes { dataBytes in
                _ = SHA256(
                    dataBytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    digestBytes.bindMemory(to: UInt8.self).baseAddress
                )
            }
        }

        return digest
    }

    func aesEncrypt(_ data: Data, withKey key: Data) -> Data {
        precondition(key.count == 16, "AES-128 key must be 16 bytes")
        precondition(data.count.isMultiple(of: 16), "AES-ECB without padding requires input length multiple of 16")

        guard let ctx = EVP_CIPHER_CTX_new() else {
            fatalError("EVP_CIPHER_CTX_new failed")
        }
        defer {
            EVP_CIPHER_CTX_free(ctx)
        }

        var ciphertext = Data(count: data.count)
        var outLen: Int32 = 0

        let initResult = key.withUnsafeBytes { keyBytes in
            EVP_EncryptInit_ex(
                ctx,
                EVP_aes_128_ecb(),
                nil,
                keyBytes.bindMemory(to: UInt8.self).baseAddress,
                nil
            )
        }

        guard initResult == 1 else {
            fatalError("EVP_EncryptInit_ex failed")
        }

        guard EVP_CIPHER_CTX_set_padding(ctx, 0) == 1 else {
            fatalError("EVP_CIPHER_CTX_set_padding failed")
        }

        let updateResult = ciphertext.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                EVP_EncryptUpdate(
                    ctx,
                    outBytes.bindMemory(to: UInt8.self).baseAddress,
                    &outLen,
                    inBytes.bindMemory(to: UInt8.self).baseAddress,
                    Int32(data.count)
                )
            }
        }

        guard updateResult == 1 else {
            fatalError("EVP_EncryptUpdate failed")
        }

        precondition(Int(outLen) == ciphertext.count, "Unexpected ciphertext length")

        return ciphertext
    }

    func aesDecrypt(data: Data, key: Data) -> Data {
        precondition(key.count == 16, "AES-128 key must be 16 bytes")
        precondition(data.count.isMultiple(of: 16), "AES-ECB without padding requires input length multiple of 16")

        guard let ctx = EVP_CIPHER_CTX_new() else {
            fatalError("EVP_CIPHER_CTX_new failed")
        }
        defer {
            EVP_CIPHER_CTX_free(ctx)
        }

        var plaintext = Data(count: data.count)
        var outLen: Int32 = 0

        let initResult = key.withUnsafeBytes { keyBytes in
            EVP_DecryptInit_ex(
                ctx,
                EVP_aes_128_ecb(),
                nil,
                keyBytes.bindMemory(to: UInt8.self).baseAddress,
                nil
            )
        }

        guard initResult == 1 else {
            fatalError("EVP_DecryptInit_ex failed")
        }

        guard EVP_CIPHER_CTX_set_padding(ctx, 0) == 1 else {
            fatalError("EVP_CIPHER_CTX_set_padding failed")
        }

        let updateResult = plaintext.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                EVP_DecryptUpdate(
                    ctx,
                    outBytes.bindMemory(to: UInt8.self).baseAddress,
                    &outLen,
                    inBytes.bindMemory(to: UInt8.self).baseAddress,
                    Int32(data.count)
                )
            }
        }

        guard updateResult == 1 else {
            fatalError("EVP_DecryptUpdate failed")
        }

        precondition(Int(outLen) == plaintext.count, "Unexpected plaintext length")

        return plaintext
    }

    func verifySignature(data: Data, signature: Data, cert: Data) -> Bool {
        let x509: OpaquePointer? = cert.withUnsafeBytes { certBytes in
            guard let baseAddress = certBytes.baseAddress else { return nil }

            let bio = BIO_new_mem_buf(baseAddress, Int32(cert.count))
            defer {
                BIO_free(bio)
            }

            guard bio != nil else { return nil }
            return PEM_read_bio_X509(bio, nil, nil, nil)
        }

        guard let x509 else {
            Log.e("Unable to parse certificate in memory")
            return false
        }
        defer {
            X509_free(x509)
        }

        guard let pubKey = X509_get_pubkey(x509) else {
            return false
        }
        defer {
            EVP_PKEY_free(pubKey)
        }

        guard let mdctx = EVP_MD_CTX_new() else {
            return false
        }
        defer {
            EVP_MD_CTX_free(mdctx)
        }

        guard EVP_DigestVerifyInit(mdctx, nil, EVP_sha256(), nil, pubKey) == 1 else {
            return false
        }

        let updateResult = data.withUnsafeBytes { dataBytes in
            EVP_DigestVerifyUpdate(mdctx, dataBytes.baseAddress, data.count)
        }

        guard updateResult == 1 else {
            return false
        }

        let finalResult = signature.withUnsafeBytes { sigBytes in
            EVP_DigestVerifyFinal(
                mdctx,
                sigBytes.bindMemory(to: UInt8.self).baseAddress,
                signature.count
            )
        }

        return finalResult > 0
    }

    func signData(_ data: Data, withKey key: Data) -> Data? {
        // Quick sanity check: expect a PEM RSA or PKCS#8 private key
//        if let header = String(data: key.prefix(64), encoding: .utf8) {
//            assert(header.contains("BEGIN RSA PRIVATE KEY") || header.contains("BEGIN PRIVATE KEY"),
//                   "Unexpected key format: \(header)")
//        }

        let pkey: OpaquePointer? = key.withUnsafeBytes { keyBytes in
            guard let baseAddress = keyBytes.baseAddress else { return nil }

            let bio = BIO_new_mem_buf(baseAddress, Int32(key.count))
            defer {
                BIO_free(bio)
            }

            guard bio != nil else { return nil }
            return PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }

        guard let pkey else {
            Log.e("Unable to parse private key in memory!")
            return nil
        }
        defer {
            EVP_PKEY_free(pkey)
        }

        guard let mdctx = EVP_MD_CTX_new() else {
            return nil
        }
        defer {
            EVP_MD_CTX_free(mdctx)
        }

        guard EVP_DigestSignInit(mdctx, nil, EVP_sha256(), nil, pkey) == 1 else {
            return nil
        }

        let updateResult = data.withUnsafeBytes { dataBytes in
            EVP_DigestSignUpdate(mdctx, dataBytes.baseAddress, data.count)
        }

        guard updateResult == 1 else {
            return nil
        }

        var sigLen = 0
        guard EVP_DigestSignFinal(mdctx, nil, &sigLen) == 1 else {
            return nil
        }

        var signature = Data(count: sigLen)

        let finalResult = signature.withUnsafeMutableBytes { sigBytes in
            EVP_DigestSignFinal(
                mdctx,
                sigBytes.bindMemory(to: UInt8.self).baseAddress,
                &sigLen
            )
        }

        guard finalResult == 1 else {
            return nil
        }

        if sigLen != signature.count {
            signature.removeSubrange(sigLen ..< signature.count)
        }

        return signature
    }
}

private extension CryptoManager {
    static func readCryptoObject(_ item: String) -> Data? {
        #if os(tvOS)
        return UserDefaults.standard.data(forKey: item)
        #else
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot get the documents directory.")
        }

        let fileURL = documentsDirectory.appendingPathComponent(item)
        return try? Data(contentsOf: fileURL)
        #endif
    }

    static func writeCryptoObject(_ item: String, data: Data) {
        #if os(tvOS)
        return UserDefaults.standard.set(data, forKey: item)
        #else
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Cannot get the documents directory.")
        }

        let fileURL = documentsDirectory.appendingPathComponent(item)
        try? data.write(to: fileURL, options: [])
        #endif
    }

    static func keyPairExists() -> Bool {
        let keyFileExists = CryptoManager.readCryptoObject("client.key") != nil
        let p12FileExists = CryptoManager.readCryptoObject("client.p12") != nil
        let certFileExists = CryptoManager.readCryptoObject("client.crt") != nil

        return keyFileExists && p12FileExists && certFileExists
    }
}

extension CryptoManager {

}

private extension CryptoManager {
    typealias X509Ref = OpaquePointer
    typealias EVP_PKEYRef = OpaquePointer
    typealias PKCS12Ref = OpaquePointer

    final class CertKeyPairObject {
        nonisolated(unsafe) let x509: X509Ref
        nonisolated(unsafe) let pkey: EVP_PKEYRef
        nonisolated(unsafe) let p12: PKCS12Ref

        init(x509: X509Ref, pkey: EVP_PKEYRef, p12: PKCS12Ref) {
            self.x509 = x509
            self.pkey = pkey
            self.p12 = p12
        }

        deinit {
            // Make sure to free these with the correct OpenSSL functions
            X509_free(x509)
            EVP_PKEY_free(pkey)
            PKCS12_free(p12)
        }
    }

    struct CertKeyPair {
        var x509: Data
        var pkey: Data
        var p12: Data
    }

    static func generateCertKeyPair() -> CertKeyPair {
        let object = generateCertKeyPairObject()

        guard let certData = getCertFromCertKeyPair(object),
              let p12Data = getP12FromCertKeyPair(object),
              let pkeyData = getKeyFromCertKeyPair(object)
        else { fatalError("KeyPair generation failed") }

        return CertKeyPair(x509: certData, pkey: pkeyData, p12: p12Data)
    }

    private static func generateCertKeyPairObject() -> CertKeyPairObject {
        var x509: X509Ref?
        var pkey: EVP_PKEYRef?
        var p12: PKCS12Ref?

        mkcert(&x509, &pkey)

        let pass = "limelight"

        p12 = PKCS12_create(
            pass,
            "GameStream",
            pkey,
            x509,
            nil,
            NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
            -1, // disable certificate encryption
            2048,
            -1, // disable the automatic MAC
            0
        )

        // MAC it ourselves with SHA1 since iOS refuses to load anything else.
        if let p12 {
            PKCS12_set_mac(p12, pass, -1, nil, 0, 1, EVP_sha1())
        }

        guard let x509, let pkey, let p12 else {
            fatalError("Error generating a valid PKCS12 certificate.")
        }

        return CertKeyPairObject(x509: x509, pkey: pkey, p12: p12)
    }

    private static func mkcert(
        _ x509p: inout OpaquePointer?,
        _ pkeyp: inout OpaquePointer?,
        _ bits: Int32 = 2048,
        _ serial: Int32 = 0,
        _ years: Int32 = 20
    ) {
        guard let cert = X509_new() else {
            x509p = nil
            pkeyp = nil
            return
        }

        guard let ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil) else {
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }
        defer {
            EVP_PKEY_CTX_free(ctx)
        }

        guard EVP_PKEY_keygen_init(ctx) == 1 else {
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        guard EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, bits) == 1 else {
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        var pk: OpaquePointer? = nil
        guard EVP_PKEY_keygen(ctx, &pk) == 1, let pk else {
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        X509_set_version(cert, 2)
        ASN1_INTEGER_set(X509_get_serialNumber(cert), Int(serial))

        if let before = ASN1_STRING_dup(X509_get0_notBefore(cert)),
           let after = ASN1_STRING_dup(X509_get0_notAfter(cert)) {
            X509_gmtime_adj(before, 0)
            X509_gmtime_adj(after, 60 * 60 * 24 * 365 * Int(years))

            X509_set1_notBefore(cert, before)
            X509_set1_notAfter(cert, after)

            ASN1_STRING_free(before)
            ASN1_STRING_free(after)
        } else {
            EVP_PKEY_free(pk)
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        X509_set_pubkey(cert, pk)

        if let name = X509_get_subject_name(cert) {
            _ = "CN".withCString { fieldName in
                "NVIDIA GameStream Client".withCString { commonName in
                    X509_NAME_add_entry_by_txt(
                        name,
                        fieldName,
                        MBSTRING_ASC,
                        UnsafePointer<UInt8>(OpaquePointer(commonName)),
                        -1,
                        -1,
                        0
                    )
                }
            }

            X509_set_issuer_name(cert, name)
        } else {
            EVP_PKEY_free(pk)
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        guard X509_sign(cert, pk, EVP_sha256()) > 0 else {
            EVP_PKEY_free(pk)
            X509_free(cert)
            x509p = nil
            pkeyp = nil
            return
        }

        x509p = cert
        pkeyp = pk
    }
}

private extension CryptoManager {
    static func getKeyFromCertKeyPair(_ certKeyPair: CertKeyPairObject) -> Data? {
        let pkey = certKeyPair.pkey
        guard let bio = BIO_new(BIO_s_mem()) else {
            return nil
        }
        defer { BIO_free(bio) }

        guard PEM_write_bio_PrivateKey_traditional(bio, pkey, nil, nil, 0, nil, nil) == 1 else {
            return nil
        }

        return dataFromMemoryBIO(bio)
    }

    static func getP12FromCertKeyPair(_ certKeyPair: CertKeyPairObject) -> Data? {
        let p12 = certKeyPair.p12
        guard let bio = BIO_new(BIO_s_mem()) else {
            return nil
        }
        defer { BIO_free(bio) }

        guard i2d_PKCS12_bio(bio, p12) == 1 else {
            return nil
        }

        return dataFromMemoryBIO(bio)
    }

    static func getCertFromCertKeyPair(_ certKeyPair: CertKeyPairObject) -> Data? {
        let x509 = certKeyPair.x509

        guard let bio = BIO_new(BIO_s_mem()) else {
            return nil
        }
        defer { BIO_free(bio) }

        guard PEM_write_bio_X509(bio, x509) == 1 else {
            return nil
        }

        return dataFromMemoryBIO(bio)
    }

    private static func dataFromMemoryBIO(_ bio: OpaquePointer?) -> Data? {
        guard let bio else { return nil }

        let pending = BIO_ctrl_pending(bio)
        guard pending >= 0 else { return nil }

        var data = Data(count: Int(pending))
        let readCount = data.withUnsafeMutableBytes { buffer in
            BIO_read(bio, buffer.baseAddress, Int32(pending))
        }

        guard readCount >= 0 else { return nil }

        if readCount < Int32(pending) {
            data.removeSubrange(Int(readCount)..<data.count)
        }

        return data
    }
}
