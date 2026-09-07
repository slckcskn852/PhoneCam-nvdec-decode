#pragma once

#include <stdexcept>
#include <functional>
#include <cstring>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

// Single decode-thread owner. Destruction must follow the client thread join.
class VideoDecoder {
public:
  explicit VideoDecoder(bool hardware, AVCodecID codecId = AV_CODEC_ID_HEVC, const AVCodecParameters* parameters = nullptr) {
    const AVCodec* decoder = avcodec_find_decoder(codecId);
    if (!decoder) throw std::runtime_error("Video decoder unavailable");
    codec_ = avcodec_alloc_context3(decoder);
    packet_ = av_packet_alloc();
    frame_ = av_frame_alloc();
    transfer_ = av_frame_alloc();
    if (!codec_ || !packet_ || !frame_ || !transfer_) { cleanup(); throw std::bad_alloc(); }
    if (parameters && avcodec_parameters_to_context(codec_, parameters) < 0) {
      cleanup(); throw std::runtime_error("Cannot configure decoder parameters");
    }
    codec_->max_pixels = 3840LL * 2160;
    codec_->flags |= AV_CODEC_FLAG_LOW_DELAY;
    codec_->thread_count = 0;
    codec_->thread_type = FF_THREAD_SLICE;
#if defined(_WIN32)
    if (hardware) {
      for (int i = 0; const auto* config = avcodec_get_hw_config(decoder, i); ++i) {
        if (config->device_type == AV_HWDEVICE_TYPE_D3D11VA &&
            (config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX)) {
          if (av_hwdevice_ctx_create(&codec_->hw_device_ctx, config->device_type, nullptr, nullptr, 0) == 0) {
            codec_->get_format = [](AVCodecContext* context, const AVPixelFormat* formats) {
              for (auto p = formats; *p != AV_PIX_FMT_NONE; ++p)
                if (*p == AV_PIX_FMT_D3D11) return *p;
              return avcodec_default_get_format(context, formats);
            };
          }
          break;
        }
      }
    }
#else
    (void)hardware;
#endif
    if (avcodec_open2(codec_, decoder, nullptr) < 0) {
      cleanup(); throw std::runtime_error("Cannot open video decoder");
    }
  }
  ~VideoDecoder() { cleanup(); }
  VideoDecoder(const VideoDecoder&) = delete;
  VideoDecoder& operator=(const VideoDecoder&) = delete;
  bool hardwareEnabled() const { return codec_->hw_device_ctx != nullptr; }

  int decode(const uint8_t* data, size_t size, uint32_t timestamp,
             const std::function<void(AVFrame*)>& output) {
    if (!data || size == 0 || size > 8 * 1024 * 1024) return 1;
    // FFmpeg requires AV_INPUT_BUFFER_PADDING_SIZE readable zero bytes.
    av_packet_unref(packet_);
    if (av_new_packet(packet_, static_cast<int>(size)) < 0) return 1;
    std::memcpy(packet_->data, data, size);
    packet_->pts = timestamp;
    int errors = 0;
    int rc = avcodec_send_packet(codec_, packet_);
    if (rc == AVERROR(EAGAIN)) {
      errors += drain(output);
      rc = avcodec_send_packet(codec_, packet_);
    }
    av_packet_unref(packet_);
    if (rc < 0) return errors + 1;
    return errors + drain(output);
  }

  int flush(const std::function<void(AVFrame*)>& output) {
    const int rc = avcodec_send_packet(codec_, nullptr);
    if (rc < 0 && rc != AVERROR_EOF) return 1;
    return drain(output);
  }

  bool convert(AVFrame* frame, int width, int height, uint8_t* bgr) {
    if (frame->width <= 0 || frame->height <= 0 || frame->width > 3840 || frame->height > 2160) return false;
    sws_ = sws_getCachedContext(sws_, frame->width, frame->height,
        static_cast<AVPixelFormat>(frame->format), width, height, AV_PIX_FMT_BGR24,
        SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
    if (!sws_) return false;
    int matrix = SWS_CS_DEFAULT;
    if (frame->colorspace == AVCOL_SPC_BT709) matrix = SWS_CS_ITU709;
    else if (frame->colorspace == AVCOL_SPC_BT2020_NCL || frame->colorspace == AVCOL_SPC_BT2020_CL) matrix = SWS_CS_BT2020;
    const int* coefficients = sws_getCoefficients(matrix);
    sws_setColorspaceDetails(sws_, coefficients, frame->color_range == AVCOL_RANGE_JPEG,
                            coefficients, 1, 0, 1 << 16, 1 << 16);
    uint8_t* dest[4] = {bgr, nullptr, nullptr, nullptr};
    int stride[4] = {width * 3, 0, 0, 0};
    return sws_scale(sws_, frame->data, frame->linesize, 0, frame->height, dest, stride) == height;
  }
private:
  int drain(const std::function<void(AVFrame*)>& output) {
    int errors = 0;
    int rc;
    while ((rc = avcodec_receive_frame(codec_, frame_)) == 0) {
      AVFrame* cpu = frame_;
      if (frame_->hw_frames_ctx) {
        av_frame_unref(transfer_);
        if (av_hwframe_transfer_data(transfer_, frame_, 0) < 0) {
          ++errors; av_frame_unref(frame_); continue;
        }
        av_frame_copy_props(transfer_, frame_);
        cpu = transfer_;
      }
      output(cpu);
      av_frame_unref(frame_);
      av_frame_unref(transfer_);
    }
    return errors + (rc != AVERROR(EAGAIN) && rc != AVERROR_EOF ? 1 : 0);
  }
  void cleanup() {
    sws_freeContext(sws_); sws_ = nullptr;
    av_frame_free(&frame_); av_frame_free(&transfer_);
    av_packet_free(&packet_); avcodec_free_context(&codec_);
  }
  AVCodecContext* codec_ = nullptr;
  AVPacket* packet_ = nullptr;
  AVFrame* frame_ = nullptr;
  AVFrame* transfer_ = nullptr;
  SwsContext* sws_ = nullptr;
};
