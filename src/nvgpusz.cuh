#ifndef CUSZ_NVGPUSZ_CUH
#define CUSZ_NVGPUSZ_CUH

/**
 * @file nvgpusz.cuh
 * @author Jiannan Tian
 * @brief Workflow of cuSZ (header).
 * @version 0.3
 * @date 2021-07-12
 * (created) 2020-02-12 (rev.1) 2020-09-20 (rev.2) 2021-07-12; (rev.3) 2021-09-06
 *
 * @copyright (C) 2020 by Washington State University, The University of Alabama, Argonne National Laboratory
 * See LICENSE in top-level directory
 *
 */

#include <cxxabi.h>
#include <clocale>
#include <iostream>
#include <unordered_map>

#include "common/capsule.hh"
#include "common/type_traits.hh"
#include "context.hh"
#include "header.hh"
#include "utils.hh"
#include "wrapper/extrap_lorenzo.cuh"
#include "wrapper/handle_sparsity10.cuh"
#include "wrapper/handle_sparsity11.cuh"
#include "wrapper/huffman_coarse.cuh"

using namespace std;

// TODO when to use ADDR8?
// TODO change to `enum class`
enum class cuszSEG { HEADER, BOOK, QUANT, REVBOOK, ANCHOR, OUTLIER, HUFF_META, HUFF_DATA };

class DataSeg {
   public:
    std::unordered_map<cuszSEG, int> name2order = {
        {cuszSEG::HEADER, 0},   {cuszSEG::BOOK, 1},    {cuszSEG::QUANT, 2},     {cuszSEG::REVBOOK, 3},
        {cuszSEG::ANCHOR, 0xa}, {cuszSEG::OUTLIER, 4}, {cuszSEG::HUFF_META, 5}, {cuszSEG::HUFF_DATA, 6}};

    std::unordered_map<int, cuszSEG> order2name = {
        {0, cuszSEG::HEADER},   {1, cuszSEG::BOOK},    {2, cuszSEG::QUANT},     {3, cuszSEG::REVBOOK},
        {0xa, cuszSEG::ANCHOR}, {4, cuszSEG::OUTLIER}, {5, cuszSEG::HUFF_META}, {6, cuszSEG::HUFF_DATA}};

    std::unordered_map<cuszSEG, uint32_t> nbyte = {
        {cuszSEG::HEADER, sizeof(cusz_header)},
        {cuszSEG::BOOK, 0U},
        {cuszSEG::QUANT, 0U},
        {cuszSEG::REVBOOK, 0U},
        {cuszSEG::ANCHOR, 0U},
        {cuszSEG::OUTLIER, 0U},
        {cuszSEG::HUFF_META, 0U},
        {cuszSEG::HUFF_DATA, 0U}};

    std::unordered_map<cuszSEG, std::string> name2str{
        {cuszSEG::HEADER, "HEADER"},       {cuszSEG::BOOK, "BOOK"},          {cuszSEG::QUANT, "QUANT"},
        {cuszSEG::REVBOOK, "REVBOOK"},     {cuszSEG::ANCHOR, "ANCHOR"},      {cuszSEG::OUTLIER, "OUTLIER"},
        {cuszSEG::HUFF_META, "HUFF_META"}, {cuszSEG::HUFF_DATA, "HUFF_DATA"}};

    std::vector<uint32_t> offset;

    uint32_t    get_offset(cuszSEG name) { return offset.at(name2order.at(name)); }
    std::string get_namestr(cuszSEG name) { return name2str.at(name); }
};

template <typename T, typename E, typename H, typename FP>
class Compressor {
    using BYTE = uint8_t;

   private:
    DataSeg dataseg;

    // clang-format off
    struct { double eb; FP ebx2, ebx2_r, eb_r; } config;
    struct { float lossy{0.0}, outlier{0.0}, hist{0.0}, book{0.0}, lossless{0.0}; } time;
    // clang-format on

    struct {
        BYTE*   h_revbook;
        size_t *h_counts, *d_counts;
        H *     h_bitstream, *d_bitstream;
    } huffman;

    T *h_anchor, *d_anchor;

    struct {
        unsigned int workspace_nbyte;
        uint32_t     dump_nbyte;
        uint8_t*     workspace;
        uint8_t*     dump;
    } sp;

    cusz::PredictorLorenzo<T, E, FP>* predictor;
    cusz::OutlierHandler10<T>*        csr;
    cusz::HuffmanWork<E, H>*          reducer;

    cuszCTX*     ctx;
    cusz_header* header;

    Capsule<T>*    in_data;  // compress-time, TODO rename
    Capsule<BYTE>* in_dump;  // decompress-time, TODO rename
    // BYTE*          dump;

    cuszWHEN timing;

    size_t cusza_nbyte;
    size_t m, mxm;

    struct {
        uint8_t *host, *dev;
    } csr_file;

    dim3 xyz;

    unsigned int tune_deflate_chunksize(size_t len);
    void         report_compression_time();

    void consolidate(bool on_cpu = true, bool on_gpu = false);

    void lorenzo_dryrun(Capsule<T>* in_data);

    Compressor&
    get_freq_and_codebook(Capsule<E>* quant, Capsule<cusz::FREQ>* freq, Capsule<H>* book, Capsule<uint8_t>* revbook);

    Compressor& analyze_compressibility(Capsule<unsigned int>* freq, Capsule<H>* book);

    Compressor& internal_eval_try_export_book(Capsule<H>* book);

    Compressor& internal_eval_try_export_quant(Capsule<E>* quant);

    void try_skip_huffman(Capsule<E>* quant);

    Compressor& try_report_time();

    Compressor& huffman_encode(Capsule<E>* quant, Capsule<H>* book);

    Compressor& pack_metadata();

    void try_report_decompression_time();

    void try_compare_with_origin(T* xdata);

    void try_write2disk(T* host_xdata);

    void huffman_decode(Capsule<E>* quant);

    void unpack_metadata();

    void prescan();

   public:
    ~Compressor();

    // v0; decompress-time in use
    Compressor(cuszCTX* _ctx, cuszWHEN _timing);
    // v0
    // void compress(Capsule<T>* in_data);

    // v1
    Compressor(cuszCTX* _ctx, Capsule<T>* _in_data);  // okay
    // v1
    Compressor(cuszCTX* _ctx, Capsule<BYTE>* _in_dump);  // TODO excl. T == BYTE
    // v1
    void compress();

    void decompress();
};

#endif
