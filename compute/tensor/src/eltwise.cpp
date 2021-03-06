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
#if defined(_USE_GENERAL) || defined(_USE_X86) || defined(_USE_NEON)
#include "cpu/tensor_computing_cpu.h"
#endif
#ifdef _USE_MALI
#include "gpu/mali/tensor_computing_mali.h"
#endif

// [1, 10, 10] + [1, 10, 10] = [1, 10, 10]
// [1, 10, 1] + [1, 1, 10] = [1, 10, 10]
// [1, 20, 10] + [10] = [1, 20, 10]
inline EE eltwise_infer_output_size_cpu(std::vector<TensorDesc> inputDesc, TensorDesc *outputDesc)
{
    if (nullptr == outputDesc) {
        CHECK_STATUS(NULL_POINTER);
    }
    U32 num = inputDesc.size();
    if (num <= 0) {
        return NOT_MATCH;
    }

    if (num == 1) {
        *outputDesc = inputDesc[0];
        return SUCCESS;
    }

    U32 arrayDimMax = 0;
    U32 minDims = inputDesc[0].nDims;
    for (U32 i = 1; i < num; i++) {
        if (inputDesc[i].nDims > inputDesc[arrayDimMax].nDims) {
            arrayDimMax = i;
        }
        if (inputDesc[i].nDims < minDims) {
            minDims = inputDesc[i].nDims;
        }
    }
    U32 nchwc8Count = 0;
    for (U32 i = 0; i < num; i++) {
        if (inputDesc[i].df == DF_NCHWC8) {
            nchwc8Count++;
            // Output from 1D-conv + 3D tensors
            if (inputDesc[i].dims[0] == 1 && minDims == 3) {
                inputDesc[i] = tensor3df(inputDesc[i].dt, DF_NCHW,
                    inputDesc[i].dims[3], inputDesc[i].dims[2], inputDesc[i].dims[1]);
            }
        }
    }

    U32 dim = inputDesc[arrayDimMax].nDims;
    *outputDesc = inputDesc[arrayDimMax];

    if (nchwc8Count > 0 && nchwc8Count != num) {
        outputDesc->df = DF_NCHW;
    }

    for (U32 i = 0; i < dim; i++) {
        for (U32 j = 0; j < num; j++) {
            if (inputDesc[j].nDims > i) {
                outputDesc->dims[i] = UNI_MAX(outputDesc->dims[i], inputDesc[j].dims[i]);
            }
        }
    }
    return SUCCESS;
}

EE eltwise_infer_output_size(
    std::vector<Tensor *> inputTensor, Tensor *outputTensor, ArchInfo_t archInfo)
{
    if (outputTensor == nullptr) {
        CHECK_STATUS(NULL_POINTER);
    }
    std::vector<TensorDesc> inputDesc = get_desc_from_tensor_ptrs(inputTensor);
    TensorDesc outputDesc = outputTensor->get_desc();
    EE ret = NOT_SUPPORTED;
    if (IS_MALI_GPU(archInfo->arch)) {
#ifdef _USE_MALI
        std::vector<GCLMemDesc> gclmemInputDescs;
        for (auto p : inputTensor) {
            gclmemInputDescs.push_back(ocl_get_desc(*p));
        }
        GCLMemDesc gclmemOutputDesc = ocl_get_desc(*outputTensor);
        ret = eltwise_infer_output_size_mali(
            inputDesc, &outputDesc, gclmemInputDescs.data(), &gclmemOutputDesc);
        for (U32 i = 0; i < inputTensor.size(); i++) {
            ocl_set_desc(inputTensor[i], gclmemInputDescs[i]);
        }
        ocl_set_desc(outputTensor, gclmemOutputDesc);
#endif
    } else {
        ret = eltwise_infer_output_size_cpu(inputDesc, &outputDesc);
    }
    outputTensor->resize(outputDesc);
    return ret;
}

EE eltwise_infer_forward_tmp_bytes(
    std::vector<Tensor> inputTensor, Tensor outputTensor, U32 *bytes, ArchInfo_t archInfo)
{
    std::vector<TensorDesc> inputDesc = get_desc_from_tensors(inputTensor);
    UNUSED(outputTensor);

    *bytes = 0;
    U32 nchwc8Count = 0;
    for (U32 i = 0; i < inputDesc.size(); i++) {
        if (inputDesc[i].df == DF_NCHWC8) {
            nchwc8Count++;
            *bytes += tensorNumBytes(inputDesc[i]);
        }
    }
    if (nchwc8Count == inputDesc.size() || nchwc8Count == 0) {
        *bytes = 0;
    }
    return SUCCESS;
}

#ifdef _USE_INT8
inline void eltwise_process_int8(F32 scale, U8 **tmp, TensorDesc *desc, U8 **input)
{
    INT8 *inQ = (INT8 *)(*input);
    dequantize_int8_to_fp16(tensorNumElements(*desc), inQ, scale, (F16 *)*tmp);
    desc->dt = DT_F16;
    *input = *tmp;
    *tmp += tensorNumElements(*desc);
}
#endif

EE eltwise(std::vector<Tensor> inputTensor,
    EltwiseParamSpec eltwiseDesc,
    Tensor tmpTensor,
    Tensor outputTensor,
    ArchInfo_t archInfo)
{
    auto arch = archInfo->arch;
    std::vector<TensorDesc> inputDesc = get_desc_from_tensors(inputTensor);
    std::vector<void *> input = get_data_from_tensors<void *>(inputTensor, arch);
    U32 tmpBytes = tmpTensor.bytes();
    void *tmp = get_ptr_from_tensor(tmpTensor, arch);
    TensorDesc outputDesc = outputTensor.get_desc();
    void *output = get_ptr_from_tensor(outputTensor, arch);
#ifdef _USE_INT8
    if (!IS_MALI_GPU(arch)) {
        for (U32 i = 0; i < inputTensor.size(); i++) {
            if (inputDesc[i].dt == DT_I8) {
                F32 scale = inputTensor[i].get_scale();
                eltwise_process_int8(scale, (U8 **)&tmp, &inputDesc[i], (U8 **)&input[i]);
            }
        }
    }
#endif

    EE ret = NOT_SUPPORTED;
    if (IS_CPU(arch)) {
#ifdef _USE_CPU
        ret = eltwise_cpu(inputDesc, input, eltwiseDesc, tmpBytes, tmp, outputDesc, output, arch);
#endif
#ifdef _USE_MALI
    } else if (IS_MALI_GPU(arch)) {
        ret = eltwise_mali(((MaliPara_t)(archInfo->archPara))->handle, inputDesc, input,
            eltwiseDesc, outputDesc, (GCLMem_t)output);
#endif
    }
    return ret;
}
