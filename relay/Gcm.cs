// relay/Gcm.cs - AES-256-GCM through Windows CNG (bcrypt.dll), for runtimes that have no AesGcm class.
//
// WHY THIS FILE EXISTS. Windows PowerShell 5.1 runs on .NET Framework 4.8, which has no AES-GCM type
// (System.Security.Cryptography.AesGcm arrived in .NET Core 3.0). Measured 2026-10-09 on the
// development machine (spike S1): "AesGcm type present: False" under 5.1.26100 / .NET Framework 4.8.9345;
// this P/Invoke round-tripped with WebCrypto both ways, and a flipped tag byte or a wrong AAD came back
// as STATUS_AUTH_TAG_MISMATCH. relay/BackendCng.ps1 loads it with Add-Type, once per process, the way
// core/Platform.ps1 loads its power-throttling type.
//
// THE TYPE NAME CARRIES A VERSION, so a later change to this source is a new type and never a clash
// with one already compiled into a long-lived session.
//
// STRICT BY CONSTRUCTION: AES-256 only (the HPKE suite's AEAD 0x0002), a 12-byte nonce and a 16-byte
// tag, nothing else. A wrong length throws ArgumentException; a tag that does not verify returns null
// and the partly decrypted buffer is cleared, so no caller can read plaintext that failed its check.
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class HordeRelayGcmV1 {
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)] static extern int BCryptOpenAlgorithmProvider(out IntPtr h, string alg, string impl, int flags);
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)] static extern int BCryptSetProperty(IntPtr h, string prop, byte[] input, int cb, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptGenerateSymmetricKey(IntPtr hAlg, out IntPtr hKey, IntPtr obj, int cbObj, byte[] secret, int cbSecret, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptEncrypt(IntPtr hKey, byte[] input, int cbInput, ref AuthInfo info, byte[] iv, int cbIv, byte[] output, int cbOutput, out int cbResult, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDecrypt(IntPtr hKey, byte[] input, int cbInput, ref AuthInfo info, byte[] iv, int cbIv, byte[] output, int cbOutput, out int cbResult, int flags);
    [DllImport("bcrypt.dll")] static extern int BCryptDestroyKey(IntPtr hKey);
    [DllImport("bcrypt.dll")] static extern int BCryptCloseAlgorithmProvider(IntPtr h, int flags);

    // BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO, version 1.
    [StructLayout(LayoutKind.Sequential)]
    struct AuthInfo {
        public int cbSize; public int dwInfoVersion; public IntPtr pbNonce; public int cbNonce; public IntPtr pbAuthData; public int cbAuthData;
        public IntPtr pbTag; public int cbTag; public IntPtr pbMacContext; public int cbMacContext; public int cbAAD; public long cbData; public int dwFlags;
    }

    const int StatusAuthTagMismatch = unchecked((int)0xC000A002);

    static void Lengths(byte[] key, byte[] nonce, byte[] aad) {
        if (key == null || key.Length != 32) throw new ArgumentException("the key must be 32 bytes (AES-256)");
        if (nonce == null || nonce.Length != 12) throw new ArgumentException("the nonce must be 12 bytes");
        if (aad == null) throw new ArgumentException("the additional data must be given, empty or not");
    }

    static byte[] Run(bool encrypt, byte[] key, byte[] nonce, byte[] aad, byte[] input, byte[] tag) {
        IntPtr alg = IntPtr.Zero, k = IntPtr.Zero;
        int st = BCryptOpenAlgorithmProvider(out alg, "AES", null, 0);
        if (st != 0) throw new InvalidOperationException("BCryptOpenAlgorithmProvider failed 0x" + st.ToString("X8"));
        // One extra byte so an empty AAD or input still has an address to pin; its length stays 0.
        byte[] aadBuf = aad.Length == 0 ? new byte[1] : aad;
        GCHandle hn = GCHandle.Alloc(nonce, GCHandleType.Pinned), ha = GCHandle.Alloc(aadBuf, GCHandleType.Pinned), ht = GCHandle.Alloc(tag, GCHandleType.Pinned);
        try {
            byte[] mode = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            st = BCryptSetProperty(alg, "ChainingMode", mode, mode.Length, 0);
            if (st != 0) throw new InvalidOperationException("BCryptSetProperty(ChainingModeGCM) failed 0x" + st.ToString("X8"));
            st = BCryptGenerateSymmetricKey(alg, out k, IntPtr.Zero, 0, key, key.Length, 0);
            if (st != 0) throw new InvalidOperationException("BCryptGenerateSymmetricKey failed 0x" + st.ToString("X8"));
            AuthInfo i = new AuthInfo();
            i.cbSize = Marshal.SizeOf(typeof(AuthInfo)); i.dwInfoVersion = 1;
            i.pbNonce = hn.AddrOfPinnedObject(); i.cbNonce = nonce.Length;
            i.pbAuthData = aad.Length == 0 ? IntPtr.Zero : ha.AddrOfPinnedObject(); i.cbAuthData = aad.Length;
            i.pbTag = ht.AddrOfPinnedObject(); i.cbTag = tag.Length;
            byte[] output = new byte[input.Length];
            byte[] inBuf = input.Length == 0 ? new byte[1] : input;
            byte[] outBuf = input.Length == 0 ? new byte[1] : output;
            int n;
            st = encrypt
                ? BCryptEncrypt(k, inBuf, input.Length, ref i, null, 0, outBuf, input.Length, out n, 0)
                : BCryptDecrypt(k, inBuf, input.Length, ref i, null, 0, outBuf, input.Length, out n, 0);
            if (!encrypt && st == StatusAuthTagMismatch) { Array.Clear(outBuf, 0, outBuf.Length); return null; }
            if (st != 0) { Array.Clear(outBuf, 0, outBuf.Length); throw new InvalidOperationException((encrypt ? "BCryptEncrypt" : "BCryptDecrypt") + " failed 0x" + st.ToString("X8")); }
            return output;
        } finally {
            hn.Free(); ha.Free(); ht.Free();
            if (k != IntPtr.Zero) BCryptDestroyKey(k);
            if (alg != IntPtr.Zero) BCryptCloseAlgorithmProvider(alg, 0);
        }
    }

    // ciphertext || tag (16 bytes), the layout HPKE and WebCrypto use.
    public static byte[] Seal(byte[] key, byte[] nonce, byte[] aad, byte[] plaintext) {
        Lengths(key, nonce, aad);
        if (plaintext == null) throw new ArgumentException("the plaintext must be given, empty or not");
        byte[] tag = new byte[16];
        byte[] ct = Run(true, key, nonce, aad, plaintext, tag);
        byte[] outp = new byte[ct.Length + 16];
        Buffer.BlockCopy(ct, 0, outp, 0, ct.Length);
        Buffer.BlockCopy(tag, 0, outp, ct.Length, 16);
        return outp;
    }

    // The plaintext, or null when the tag does not verify (or the input is shorter than a tag).
    public static byte[] Open(byte[] key, byte[] nonce, byte[] aad, byte[] sealedBytes) {
        Lengths(key, nonce, aad);
        if (sealedBytes == null || sealedBytes.Length < 16) return null;
        byte[] ct = new byte[sealedBytes.Length - 16];
        byte[] tag = new byte[16];
        Buffer.BlockCopy(sealedBytes, 0, ct, 0, ct.Length);
        Buffer.BlockCopy(sealedBytes, ct.Length, tag, 0, 16);
        return Run(false, key, nonce, aad, ct, tag);
    }
}
