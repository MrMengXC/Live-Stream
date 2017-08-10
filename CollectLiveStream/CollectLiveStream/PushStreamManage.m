//
//  PushStreamManage.m
//  SFFmpegIOSStreamer
//
//  Created by ios on 17/7/30.
//  Copyright © 2017年 Lei Xiaohua. All rights reserved.
//

#import "PushStreamManage.h"
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>
#include <libavutil/time.h>
@interface PushStreamManage()
{
    
//    它是FFMPEG解封装（flv，mp4，rmvb，avi）功能的结构体。
    AVFormatContext* formatContext;
    
    
    AVOutputFormat *outputFormat;
//    AVFrame结构体一般用于存储原始数据（即非压缩数据，例如对视频来说是YUV，RGB，对音频来说是PCM）
    
    
    AVStream *stream;
//    ：AVCodecContext中很多的参数是编码的时候使用的
    AVCodecContext* pCodecCtx;
    
    AVCodec* pCodec;

    AVPacket packet;
    AVFrame *frame;

}
@end

@implementation PushStreamManage



- (void)manage
{
    char *rtmpPath;
    int in_w=480,in_h=272;                              //Input data's width and height
    int picture_size;
    uint8_t* picture_buf;
    int y_size;
    int framenum=100;                                   //Frames to encode
    int framecnt=0;

    
    
    av_register_all();//注册FFmpeg所有编解码器。
    
    formatContext = avformat_alloc_context();
    

    
    
    // //初始化输出码流的AVFormatContext。函数执行成功的话，其返回值大于等于0。
   int res = avformat_alloc_output_context2(&formatContext,
                                   NULL,
                                   "flv",//指定输出格式的名称。根据格式名称，FFmpeg会推测输出格式
                                   rtmpPath);//指定输出文件的名称。根据文件名称，FFmpeg会推测输出格式。
    
    outputFormat = formatContext->oformat;
    
    //打开输出文件

    if((avio_open(&formatContext->pb,
              rtmpPath,//输入输出协议的地址（文件也是一种“广义”的协议，对于文件来说就是文件的路径）
              AVIO_FLAG_READ_WRITE//打开地址的方式。
                   )< 0))
       {
           NSLog(@"open faile");
           
           return;
       }
    

    
    //创建流通道
    if((stream = avformat_new_stream(formatContext, 0)) == NULL)
    {
        NSLog(@"stream null");
        return;
    }
    //Param that must set
    pCodecCtx = stream->codec;
    //pCodecCtx->codec_id =AV_CODEC_ID_HEVC;
    pCodecCtx->codec_id = AV_CODEC_ID_H264;//outputFormat->video_codec;
    pCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    pCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    pCodecCtx->width = in_w;
    pCodecCtx->height = in_h;
    pCodecCtx->bit_rate = 400000;
    pCodecCtx->gop_size=250;
    
    pCodecCtx->time_base.num = 1;
    pCodecCtx->time_base.den = 30;
    
    //H264
    //pCodecCtx->me_range = 16;
    //pCodecCtx->max_qdiff = 4;
    //pCodecCtx->qcompress = 0.6;
    
    //最大和最小量化系数
    pCodecCtx->qmin = 10;
    pCodecCtx->qmax = 51;
    
    //Optional Param
    pCodecCtx->max_b_frames=3;
    
    // Set Option
    AVDictionary *param = 0;
    
    //H.264
    if(pCodecCtx->codec_id == AV_CODEC_ID_H264) {
        av_dict_set(&param, "preset", "slow", 0);
        av_dict_set(&param, "tune", "zerolatency", 0);
        //av_dict_set(¶m, "profile", "main", 0);
    }
    //H.265
    if(pCodecCtx->codec_id == AV_CODEC_ID_H265){
        av_dict_set(&param, "preset", "ultrafast", 0);
        av_dict_set(&param, "tune", "zero-latency", 0);
    }
    
//    av_dump_format()是一个手工调试的函数，能使我们看到pFormatCtx->streams里面有什么内容。一般接下来我们使用av_find_stream_info()函数，它的作用是为pFormatCtx->streams填充上正确的信息。
    //函数的作用就是检查下初始化过程中设置的参数是否符合规范
    av_dump_format(formatContext, 0, rtmpPath, 1);

    //查找编码器
   if((pCodec = avcodec_find_encoder(pCodecCtx->codec_id)) == NULL)
      {
          NSLog(@"查找编码器失败");
          return;
      }

    
    //打开编码器
    if(avcodec_open2(pCodecCtx,//需要初始化的AVCodecContext。
                  pCodec, //输入的AVCodec
                  &param) != 0)
    {
        NSLog(@"打开编码器失败");
        return;
    }
    
    
    //-----
    
    frame = av_frame_alloc();
    picture_size = avpicture_get_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    picture_buf = (uint8_t *)av_malloc(picture_size);
    avpicture_fill((AVPicture *)frame, picture_buf, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    

    av_new_packet(&packet,picture_size);
    
    y_size = pCodecCtx->width * pCodecCtx->height;

    for (int i=0; i<framenum; i++)
    {
        //Read raw YUV data
//        if (fread(picture_buf, 1, y_size*3/2, in_file) <= 0){
//            printf("Failed to read raw data! \n");
//            return -1;
//        }else if(feof(in_file)){
//            break;
//        }
        frame->data[0] = picture_buf;              // Y
        frame->data[1] = picture_buf+ y_size;      // U
        frame->data[2] = picture_buf+ y_size*5/4;  // V
        //PTS
        //pFrame->pts=i;
        frame->pts=i*(stream->time_base.den)/((stream->time_base.num)*25);
        
        int got_picture=0;
        //Encode
        int ret = avcodec_encode_video2(pCodecCtx, &packet,frame, &got_picture);
        if(ret < 0){
            printf("Failed to encode! \n");
            return;
        }
        if (got_picture==1)
        {
            NSLog(@"Succeed to encode frame: %5d\tsize:%5d\n",framecnt,packet.size);
                  
            framecnt++;
            packet.stream_index = stream->index;
                  //将编码后的视频码流写入文件。
            ret =  av_write_frame(formatContext, &packet);
                  
            av_free_packet(&packet);
        }
    }

    
    
    
    //Flush Encoder
    int ret = flush_encoder(formatContext,0);
    if (ret < 0) {
        NSLog(@"Flushing encoder failed\n");
        return;
    }
    
    
    
    
////    写文件头（对于某些没有文件头的封装格式，不需要此函数。比如说MPEG2TS）。
//    
//    avformat_write_header(formatContext, NULL);
//    //编码一帧视频。即将AVFrame（存储YUV像素数据）编码为AVPacket（存储H.264等格式的码流数据）。
////    avctx：编码器的AVCodecContext。
////    avpkt：编码输出的AVPacket。
////    frame：编码输入的AVFrame。
////    got_packet_ptr：成功编码一个AVPacket的时候设置为1。
//    int got_picture = 0;
//
//    avcodec_encode_video2(pCodecCtx, &packet, frame, &got_picture);
    
    
    
    

    //写文件尾（对于某些没有文件头的封装格式，不需要此函数。比如说MPEG2TS）。
    //Write file trailer
    av_write_trailer(formatContext);
    
//    //Clean
//    if (video_st){
//        avcodec_close(video_st->codec);
//        av_free(pFrame);
//        av_free(picture_buf);
//    }
//    avio_close(pFormatCtx->pb);
//    avformat_free_context(pFormatCtx);
//    
//    fclose(in_file);
//    
//    return 0;
    

}

//输入的像素数据读取完成后调用此函数。用于输出编码器中剩余的AVPacket。
int flush_encoder(AVFormatContext *fmt_ctx,unsigned int stream_index)
{
    int ret;
    int got_frame;
    AVPacket enc_pkt;
    if (!(fmt_ctx->streams[stream_index]->codec->codec->capabilities &
          CODEC_CAP_DELAY))
        return 0;
    
    while (1) {
        enc_pkt.data = NULL;
        enc_pkt.size = 0;
        av_init_packet(&enc_pkt);
        ret = avcodec_encode_video2 (fmt_ctx->streams[stream_index]->codec, &enc_pkt,
                                     NULL, &got_frame);
        av_frame_free(NULL);
        if (ret < 0)
            break;
        if (!got_frame){
            ret=0;
            break;
        }
        printf("Flush Encoder: Succeed to encode 1 frame!\tsize:%5d\n",enc_pkt.size);
        /* mux encoded frame */
        ret = av_write_frame(fmt_ctx, &enc_pkt);
        if (ret < 0)
            break;
    }
    return ret;
}

@end
