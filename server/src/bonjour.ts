/**
 * Bonjour publish options for the iScan server.
 *
 * bonjour-service defaults the SRV target to the bare OS hostname (e.g. "XI-Laptop."), which
 * an iPhone can't resolve over mDNS. The target has to be a ".local" name.
 */
export function advertisement(hostname: string, port: number) {
  const host = hostname.toLowerCase().endsWith(".local") ? hostname : `${hostname}.local`;
  return { name: "iScan", type: "iscan", port, host };
}
