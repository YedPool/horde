// relays/cloudflare/worker/client-address.js - WHO IS ASKING, BY ADDRESS: the caller's IP as Cloudflare
// reports it, which the limits on an address are kept by (address.js, limits.js).
//
// THE ADDRESS is CF-Connecting-IP, which a caller cannot set: Cloudflare writes it over whatever the
// request carried. A request with none (a local dev answers one from this machine) is the address
// "local", and so is one whose header is not an IP's characters.
//
// THE TEST OVERRIDE. A suite needs several addresses from one machine, so with the test limits binding
// (limits.js, THE TEST OVERRIDE) - and only then, and only for a request made to this machine itself,
// which a deployed Worker never is - the header Horde-Test-Client-Address names it instead.
import { isLoopback } from "./site.js";

const TEST_HEADER = "Horde-Test-Client-Address";
const TEST_BINDING = "HORDE_RELAY_TEST_LIMITS";
const ADDRESS = /^[0-9A-Fa-f.:]{1,45}$/;

export function clientAddressOf(request, env, url) {
  if (typeof env[TEST_BINDING] === "string" && isLoopback(url)) {
    const t = request.headers.get(TEST_HEADER);
    if (typeof t === "string" && ADDRESS.test(t)) return t;
  }
  const ip = request.headers.get("CF-Connecting-IP");
  return typeof ip === "string" && ADDRESS.test(ip) ? ip : "local";
}
