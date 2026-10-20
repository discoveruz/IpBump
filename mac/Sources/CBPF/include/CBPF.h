#ifndef CBPF_H
#define CBPF_H

/// Opens the first free /dev/bpfN, binds it to the interface and lets only ARP frames through.
/// Reads return at the latest after read_timeout_ms. Returns the file descriptor, or -errno.
int ipb_bpf_open(const char *ifname, unsigned int read_timeout_ms);

/// The size every read() on this descriptor must ask for; BPF refuses any other. -errno on failure.
int ipb_bpf_buffer_length(int fd);

/// The interface's Ethernet address. 0 on success, -1 when it has none.
int ipb_interface_mac(const char *ifname, unsigned char mac[6]);

#endif
