# ARP

The ARP subsystem resolves IPv4 addresses to Ethernet MAC addresses, answers
requests for the configured local address, and learns source mappings from
received ARP and IPv4 traffic.

## Structure

```text
ARP receive header or TCP lookup request
  -> arp_top_level
  -> arp_ctrl
      -> four-way cache
      -> retry timer
      -> stale-entry timer
  -> ARP transmit descriptor or resolved MAC response
```

`arp_top_level` gives queued ARP headers priority over application lookup
requests. `arp_ctrl` contains a four-way, 16-set cache. The low four bits of
the IPv4 address select the set and the remaining 28 bits form the tag.

## Current Behavior

| Event | Behavior |
| --- | --- |
| Request for the local IPv4 address | Emit an ARP reply descriptor using the sender address. |
| Received ARP packet | Learn or refresh the sender IP/MAC mapping and report it to pending clients. |
| Accepted IPv4/TCP packet | Passively learn or refresh its source IP/MAC mapping. |
| Lookup of a reachable entry | Return the cached IP/MAC pair. |
| Lookup miss | Allocate an invalid, failed, or stale entry and emit a broadcast ARP request. |
| Stale entry lookup | Return the cached MAC, transition to `DELAY`, and begin refresh handling. |
| Entry in `PROBE` | Withhold the stale MAC while probing. |
| Retry exhaustion | Mark the entry failed and invalidate it. |

Replacement considers an invalid entry first, followed by entries in `FAILED`
or `STALE`. If all four ways in the selected set are active in other states,
the lookup cannot allocate a new entry.

The stale timer moves a valid `REACHABLE` entry to `STALE`. The retry timer
drives requests for `INCOMPLETE`, `DELAY`, and `PROBE` entries and eventually
invalidates entries that do not resolve.

## Limitations

- The receive path does not currently validate ARP hardware type, protocol
  type, address lengths, or every opcode before learning the sender mapping.
- Gratuitous ARP, proxy ARP, reverse ARP, and conflict detection do not have
  dedicated policies.
- There is no ARP spoofing protection.
- The cache has no LRU policy; replacement is based only on validity and ARP
  state.
- IPv6 Neighbor Discovery is outside this subsystem.
