// Copyright (C) 2019. Huawei Technologies Co., Ltd. All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#include "tensor_computing.h"
#include "ut_util.h"

int poolingTest(int argc, char **argv, DataType dt)
{
    CHECK_REQUIREMENT(argc == 15);
    // in data
    U32 in = atoi(argv[1]);
    U32 ic = atoi(argv[2]);
    U32 ih = atoi(argv[3]);
    U32 iw = atoi(argv[4]);
    // weight
    U32 fn = atoi(argv[5]);
    U32 fc = atoi(argv[6]);
    U32 fh = atoi(argv[7]);
    U32 fw = atoi(argv[8]);
    // stride & padding
    U32 stride = atoi(argv[9]);
    U32 padding = atoi(argv[10]);
    // output
    U32 on = atoi(argv[11]);
    U32 oc = atoi(argv[12]);
    U32 oh = atoi(argv[13]);
    U32 ow = atoi(argv[14]);
    CHECK_REQUIREMENT(in == 1 && fn == 1 && fc == 1);
    CHECK_REQUIREMENT(ic == oc && ic % 8 == 0);
    ArchInfo archInfo;
    archInfo.arch = UT_ARCH;
    ArchInfo archInfo_org;
    archInfo_org.arch = CPU_GENERAL;

    PoolingParamSpec poolingParamSpec;
    poolingParamSpec.mode = POOLING_MAX;

    poolingParamSpec.stride_h = stride;
    poolingParamSpec.stride_w = stride;
    poolingParamSpec.padding_top = padding;
    poolingParamSpec.padding_bottom = padding;
    poolingParamSpec.padding_left = padding;
    poolingParamSpec.padding_right = padding;
    poolingParamSpec.kernel_h = fh;
    poolingParamSpec.kernel_w = fw;
    poolingParamSpec.rm = CEIL;

    Tensor inputTensor;
    TensorDesc inputDesc = tensor4df(dt, DF_NCHWC8, in, ic, ih, iw);
    inputTensor.resize(inputDesc);
    inputTensor.alloc();
    U32 input_len = tensorNumElements(inputDesc);
    U8 *input = ut_input_v(input_len, dt, UT_INIT_RANDOM);
    memcpy(get_ptr_from_tensor(inputTensor, UT_ARCH), input, tensorNumBytes(inputDesc));

    // set output
    Tensor outputTensor, outputTensorRef;
    CHECK_STATUS(
        pooling_infer_output_size(&inputTensor, poolingParamSpec, &outputTensor, &archInfo));
    outputTensor.alloc();
    TensorDesc outputDesc_ref = outputTensor.get_desc();
    outputTensorRef.resize(outputDesc_ref);
    outputTensorRef.alloc();
    U32 output_len = outputTensor.length();
    CHECK_REQUIREMENT(input_len == in * ic * ih * iw && output_len == on * oc * oh * ow);
    Tensor tmpTensor;
    if (UT_CHECK) {
        CHECK_STATUS(pooling(inputTensor, poolingParamSpec, tmpTensor, outputTensor, &archInfo));

        CHECK_STATUS(
            pooling(inputTensor, poolingParamSpec, tmpTensor, outputTensorRef, &archInfo_org));
        // check
        ut_check_v(get_ptr_from_tensor(outputTensor, UT_ARCH),
            get_ptr_from_tensor(outputTensorRef, UT_ARCH), output_len, dt, 0.05, __FILE__, __LINE__);
    }

    // benchmark
    double time_start = ut_time_ms();
    for (int iter = 0; iter < UT_LOOPS; iter++) {
        CHECK_STATUS(pooling(inputTensor, poolingParamSpec, tmpTensor, outputTensor, &archInfo));
    }
    double time_end = ut_time_ms();
    double time = (time_end - time_start) / UT_LOOPS;

    // log performance data
    char buffer[150];
    char params[120];
    sprintf(params, "(%u %u %u %u)+(%u %u %u %u)/(%u %u)=(%u %u %u %u)", in, ic, ih, iw, fn, fc, fh,
        fw, stride, padding, on, oc, oh, ow);
    sprintf(buffer, "%20s, %80s", "Pooling", params);
    double ops = 1.0 * on * oc * oh * ow * fh * fw;
    ut_log(dt, buffer, ops, time);

    free(input);
    return 0;
}

int main(int argc, char **argv)
{
#ifdef _USE_FP16
    poolingTest(argc, argv, DT_F16);
#endif
#ifdef _USE_FP32
    poolingTest(argc, argv, DT_F32);
#endif
    return 0;
}
