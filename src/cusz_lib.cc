/**
 * @file cusz_lib.cc
 * @author Jiannan Tian
 * @brief
 * @version 0.3
 * @date 2022-05-01
 * (rev.1) 2023-01-29
 *
 * (C) 2022 by Washington State University, Argonne National Laboratory
 *
 */

#include <iostream>
#include <stdexcept>

using std::cout;
using std::endl;

#include "compressor.hh"
#include "context.h"
#include "cusz.h"
#include "cusz/custom.h"
#include "cusz/type.h"
#include "framework.hh"
#include "hf/hf.hh"

cusz_compressor* cusz_create(cusz_framework* _framework, cusz_datatype _type)
{
    auto comp = new cusz_compressor{.framework = _framework, .type = _type};

    if (comp->type == FP32) {
        using DATA       = float;
        using Compressor = cusz::CompressorFP32;

        comp->compressor = new Compressor();
    }
    else {
        throw std::runtime_error("Type is not supported.");
    }

    return comp;
}

cusz_error_status cusz_release(cusz_compressor* comp)
{
    if (comp->compressor) {
        using DATA       = float;
        using Compressor = cusz::CompressorFP32;

        Compressor* compressor = static_cast<Compressor*>(comp->compressor);
        delete compressor;
    }
    delete comp;
    return CUSZ_SUCCESS;
}

cusz_error_status cusz_compress(
    cusz_compressor* comp,
    cusz_config*     config,
    void*            uncompressed,
    cusz_len const   uncomp_len,
    uint8_t**        compressed,
    size_t*          comp_bytes,
    cusz_header*     header,
    void*            record,
    cudaStream_t     stream)
{
    // cusz::TimeRecord cpp_record;

    auto ctx = new cusz_context;

    pszctx_set_len(ctx, uncomp_len);

    ctx->eb   = config->eb;
    ctx->mode = config->mode;

    // Be cautious of autotuning! The default value of pardeg is not robust.
    cusz::CompressorHelper::autotune_coarse_parvle(static_cast<cusz_context*>(ctx));

    if (comp->type == FP32) {
        using DATA       = float;
        using Compressor = cusz::CompressorFP32;

        // TODO add memlen & datalen comparison
        static_cast<Compressor*>(comp->compressor)->init(ctx);
        static_cast<Compressor*>(comp->compressor)
            ->compress(ctx, static_cast<DATA*>(uncompressed), *compressed, *comp_bytes, stream);
        static_cast<Compressor*>(comp->compressor)->export_header(*header);
        static_cast<Compressor*>(comp->compressor)->export_timerecord((cusz::TimeRecord*)record);
    }
    else {
        throw std::runtime_error(std::string(__FUNCTION__) + ": Type is not supported.");
    }

    delete ctx;

    return CUSZ_SUCCESS;
}

cusz_error_status cusz_decompress(
    cusz_compressor* comp,
    cusz_header*     header,
    uint8_t*         compressed,
    size_t const     comp_len,
    void*            decompressed,
    cusz_len const   decomp_len,
    void*            record,
    cudaStream_t     stream)
{
    // cusz::TimeRecord cpp_record;

    if (comp->type == FP32) {
        using DATA       = float;
        using Compressor = cusz::CompressorFP32;

        static_cast<Compressor*>(comp->compressor)->init(header);
        static_cast<Compressor*>(comp->compressor)
            ->decompress(header, compressed, static_cast<DATA*>(decompressed), stream);
        static_cast<Compressor*>(comp->compressor)->export_timerecord((cusz::TimeRecord*)record);
    }
    else {
        throw std::runtime_error(std::string(__FUNCTION__) + ": Type is not supported.");
    }

    return CUSZ_SUCCESS;
}