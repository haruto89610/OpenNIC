# Top-Level Architecture

![Top-level block diagram](assets/top_level.png)

The `top_level` module connects the Ethernet PCS/PMA interface to the protocol
and application logic in the 125 MHz GMII clock domain.

## Receive Path

```text
SFP / PCS-PMA
  -> GMII receive interface
  -> rx_datapath
      -> ARP header path
      -> IPv4/TCP header path
      -> IPv4/UDP application path
```

`rx_datapath` strips the Ethernet preamble and decodes the supported Ethernet,
ARP, IPv4, TCP, and UDP fields. The top level admits TCP traffic only when the
destination MAC and IPv4 address match the configured local values. ARP traffic
is forwarded to `arp_top_level`.

The current top level also contains a fixed-format UDP descriptor entry point.
It translates a valid descriptor with an embedded 16-byte TCP payload into an
`app_req_in` request for the TCP subsystem. This is an application integration
point rather than part of the generic TCP state machinery. The transmit-memory
implementation behind this interface is intentionally omitted because it is
shared with ongoing private architectural work.

## Transmit Path

```text
ARP or TCP descriptor
  -> tx_datapath
  -> transmit queue
  -> Ethernet preamble / payload / FCS serializer
  -> GMII transmit interface
  -> PCS-PMA / SFP
```

`tx_datapath` arbitrates between ARP and TCP descriptors and constructs the
Ethernet frame image. The transmit queue decouples descriptor formatting from
the byte-wide GMII serializer. The serializer adds the preamble, minimum-frame
padding, FCS, and inter-frame gap.

## Clock and Reset Domains

The differential system clock produces a 200 MHz fabric clock and a divided
50 MHz independent clock for the PCS/PMA. The PCS/PMA user clock is buffered as
the 125 MHz datapath clock. Reset assertion is asynchronous to each domain;
release is synchronized independently in the 50 MHz and 125 MHz domains.
