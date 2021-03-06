#ifndef H_GCL_KERNEL_TYPE_H
#define H_GCL_KERNEL_TYPE_H

struct GCLKernelBin {
    const unsigned char *data;
    const unsigned int len;
};

struct GCLKernelSource {
    const char *data;
    const unsigned int len;
    bool use_kernel_def_head;
};

struct GCLKernelOption {
    const char *option;
    const char *sourceName;
    bool use_common_opt;
};
#endif
