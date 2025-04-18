# HEVC视频转码脚本

本脚本为用户将用于上传到飞机的视频文件转换为HEVC编码格式，并支持自动码率的调整。

## 安装步骤

1. 确保系统已安装ffmpeg和ffprobe（版本>=4.0）
2. 下载本脚本并赋予可执行权限：
   ```bash
   chmod +x convert2hevc.sh
   ```
3. 将脚本添加到系统PATH中以便全局使用

## 使用说明

基本用法：
```bash
./convert2hevc.sh input.mp4
```

可选参数：


## 示例

1. 基本转换：
   ```bash
   ./convert2hevc.sh input_video.mp4
   ```

## 常见问题

Q: 转码过程中出现错误怎么办？

A: 请检查输入文件格式是否支持，并确保ffmpeg版本符合要求。

Q: 转码后视频质量如何？

A: 转码后视频质量取决于输入文件的原始质量和码率设置。建议在转码前进行必要的质量评估和调整。

Q: 如何中断转码并清理临时文件？

A: 按下Ctrl+C即可中断转码并清理临时文件。

Q: 转码完成后如何打开输出目录？

A: 脚本会在转码完成后询问是否打开输出目录。输入'y'即可打开输出目录。

Q: 脚本支持哪些视频格式？

A: 脚本支持常见的视频格式，如MP4、AVI、MKV等。请确保输入文件格式正确。

Q: 如何调整码率？

A: 脚本会根据输入文件大小自动调整码率。如果需要手动调整码率，可以在脚本中修改预设值。

Q: 脚本支持哪些操作系统？

A: 脚本支持Linux、macOS系统。请根据实际情况选择合适的操作系统。

Q: 如何获取更多帮助？

A: 您可以通过提交问题或联系脚本作者获取更多帮助。

## 功能特性

- 自动检测ffmpeg和ffprobe依赖
- 动态计算压缩比，优化输出文件大小
- 根据CPU核心数智能选择转码预设模式
- 实时显示转码进度和预估时间
- 支持大文件自动降低码率（默认阈值2GB）
  - 当文件小于2GB时，使用原始码率
  - 当文件大于2GB时，自动计算目标码率
  - 目标码率计算公式：(2.048 * 1024 * 1024 * 8) / 时长 * 0.91
- 提供码率变更警告提示
- 支持中断后清理临时文件
- 转码完成后可自动打开输出目录

## 使用方法

```bash
./convert2hevc.sh <视频文件路径>
```

## 依赖要求

- ffmpeg >= 4.0
- ffprobe >= 4.0

## 参数说明

- `<视频文件路径>`：需要转码的视频文件路径

## 注意事项

1. 当输入文件大于2GB时，脚本会自动降低码率，可能会影响画质
2. 转码过程中按Ctrl+C可中断并清理临时文件
3. 转码完成后会询问是否打开输出目录
4. 建议使用macOS系统运行脚本
5. 转码过程中请保持终端窗口打开

## 示例

```bash
./convert2hevc.sh /path/to/video.mp4
```

## 作者

Tartoruz

## 版本

1.0.0