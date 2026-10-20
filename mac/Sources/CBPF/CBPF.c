#include "CBPF.h"

#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/bpf.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

int ipb_bpf_open(const char *ifname, unsigned int read_timeout_ms) {
    int fd = -1;
    for (int i = 0; i < 256 && fd < 0; i++) {
        char path[16];
        snprintf(path, sizeof path, "/dev/bpf%d", i);
        fd = open(path, O_RDWR);
        if (fd < 0 && errno != EBUSY) return -errno;   // EBUSY: another program has this one
    }
    if (fd < 0) return -EBUSY;

    struct ifreq ifr;
    memset(&ifr, 0, sizeof ifr);
    strlcpy(ifr.ifr_name, ifname, sizeof ifr.ifr_name);
    unsigned int length = 32768, on = 1, off = 0;
    struct timeval timeout = { .tv_sec = read_timeout_ms / 1000, .tv_usec = (read_timeout_ms % 1000) * 1000 };
    struct bpf_insn program[] = {
        BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 12),                     // the Ethernet type
        BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, ETHERTYPE_ARP, 0, 1),
        BPF_STMT(BPF_RET + BPF_K, 65535),                           // ARP: keep all of it
        BPF_STMT(BPF_RET + BPF_K, 0),                               // anything else: drop
    };
    struct bpf_program filter = { .bf_len = sizeof program / sizeof program[0], .bf_insns = program };

    // The buffer size has to be set before the interface is
    if (ioctl(fd, BIOCSBLEN, &length) < 0 || ioctl(fd, BIOCSETIF, &ifr) < 0
        || ioctl(fd, BIOCIMMEDIATE, &on) < 0           // hand packets over as they arrive
        || ioctl(fd, BIOCSHDRCMPLT, &on) < 0           // our frames carry their own source address
        || ioctl(fd, BIOCSSEESENT, &off) < 0           // don't read back what this Mac sends
        || ioctl(fd, BIOCSRTIMEOUT, &timeout) < 0 || ioctl(fd, BIOCSETF, &filter) < 0) {
        int error = errno;
        close(fd);
        return -error;
    }
    return fd;
}

int ipb_bpf_buffer_length(int fd) {
    unsigned int length = 0;
    if (ioctl(fd, BIOCGBLEN, &length) < 0) return -errno;
    return (int)length;
}

int ipb_interface_mac(const char *ifname, unsigned char mac[6]) {
    struct ifaddrs *list;
    if (getifaddrs(&list) != 0) return -1;
    int found = -1;
    for (struct ifaddrs *a = list; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_LINK || strcmp(a->ifa_name, ifname) != 0) continue;
        struct sockaddr_dl *link = (struct sockaddr_dl *)a->ifa_addr;
        if (link->sdl_alen == 6) {
            memcpy(mac, LLADDR(link), 6);
            found = 0;
        }
        break;
    }
    freeifaddrs(list);
    return found;
}
