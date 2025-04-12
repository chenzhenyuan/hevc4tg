#!/usr/bin/env bash

LIMIT_SIZE_GB=2

throwError() {
  printf "\033[31m错误：%s\033[0m\n" "$*"
}

# 检查依赖
check_dependencies() {
  for cmd in ffmpeg ffprobe; do
    if ! command -v $cmd &>/dev/null; then
      throwError "未找到$cmd，请安装$cmd（版本>=4.0）"
      exit 1
    fi
  done
}

# 检查版本
check_version() {
  local version=$($1 -version | head -n1 | cut -d' ' -f3)
  if [[ "$(echo "$version 4.0" | tr ' ' '\n' | sort -V | head -n1)" != "4.0" ]]; then
    throwError "$1版本过低（当前：$version），需要4.0+"
    exit 1
  fi
}

# 格式化时间
# 输入：秒数
# 输出：HH:MM:SS.fff
format_duration() {
  local duration=$1
  local hours=$(echo "scale=0; $duration / 3600" | bc)
  local minutes=$(echo "scale=0; ($duration % 3600) / 60" | bc)
  local seconds=$(echo "$duration % 60" | bc)

  printf "%02d:%02d:%06.3f" $hours $minutes $seconds

}

# 动态计算压缩比
calc_compression_ratio() {
  local orig_bitrate=$1
  echo "scale=2; 0.85 + (($orig_bitrate - 5000)/50000)" | bc
}

# 智能选择preset
get_optimal_preset() {
  local cpu_cores=$(sysctl -n hw.ncpu)
  ((cpu_cores >= 8)) && echo "slow" || echo "medium"
}

# 绘制分割线
separator() {
  local print_width=$(tput cols)
  printf '%0.s-' $(seq 1 $print_width)
  printf "\n"
}

# 主流程
main() {
  check_dependencies
  check_version ffmpeg
  check_version ffprobe

  [[ $# -eq 0 ]] && {
    echo "Usage: $(basename "$0") <视频路径>"
    exit 1
  }

  local input_file=$1

  [[ ! -f "$input_file" ]] && {
    throwError "文件不存在: $input_file"
    exit 1
  }

  # 获取视频信息
  local ori_duration=$(ffprobe -hide_banner -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
  local original_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$input_file")
  local original_bitrate_kbps=$(echo "scale=2; $original_bitrate / 1000" | bc)

  local file_size_bytes=$(wc -c <"$input_file" | tr -d ' ')
  local file_size_mb=$(echo "scale=3; $file_size_bytes / 1024 / 1024" | bc)
  local file_size_gb=$(echo "scale=3; $file_size_mb / 1024" | bc)

  # 计算目标码率
  local bitrate compression_ratio
  if (($(echo "$file_size_gb < $LIMIT_SIZE_GB" | bc -l))); then
    bitrate=$original_bitrate_kbps
  else
    compression_ratio=$(calc_compression_ratio $original_bitrate_kbps)
    bitrate=$(echo "scale=2; (2.048*1024*1024*8)/$ori_duration*$compression_ratio" | bc | awk '{printf "%.0f",$1}')

    # 码率变化警告
    local bitrate_diff_pct=$(echo "scale=2;($original_bitrate_kbps-$bitrate)/$original_bitrate_kbps*100" | bc)
    (($(echo "$bitrate_diff_pct > 30" | bc -l))) && {
      printf "\033[33m警告：码率降低%.2f%%，建议检查画质！\n码率: \033[0m\033[1;32m%.2f kbps\033[0m → \033[1;31m%.2f kbps\033[0m\n" \
        $bitrate_diff_pct $original_bitrate_kbps $bitrate

      read -p "是否继续？按任意键退出，按Yy键继续。[Yy]" -n 1 -r

      [[ ! $REPLY =~ ^[Yy]$ ]] && {
        printf "\r$(tput cuu 1)$(tput el)" # 换行，避免覆盖
        printf "\033[31m(未转码，已退出)\033[0m\n"
        exit 1
      }

      printf "\r$(tput el)" # 换行，避免覆盖
    }
  fi

  # 准备输出
  local base_name=$(basename "${input_file%.*}")
  local dir_path=$(dirname "$input_file")
  local output_file="${dir_path}/${base_name}.h265.mp4"
  local preset=$(get_optimal_preset)

  # 显示信息
  separator
  # printf "%12.12s: %s\n" "视频名称" $(basename "${input_file}")
  # printf "%12.12s: %s\n" "输出目录" "$dir_path"
  printf "%12.12s: %.2f 秒\n" "视频时长" "$ori_duration"
  printf "%12.12s: %-28s\n" "预设模式" "$preset"
  printf "%12.12s: \033[1;32m%.2f kbps\033[0m → \033[1;31m%.2f kbps\033[0m\n" "码率变更" "$original_bitrate_kbps" "$bitrate"
  printf "%12.12s: %.8s \n" "预计耗时" $(format_duration $(echo "$file_size_bytes * 8 / $bitrate / 1000" | bc))

  separator

  trap 'cleanup "$output_file"' SIGINT

  printf "开始转码...\n"

  local start_time=$(date +%s)
  ffmpeg -y -hide_banner -v error -stats -progress pipe:1 -i "$input_file" -c:a copy -c:v libx265 -preset "$preset" -b:v ${bitrate}k -vtag hvc1 -x265-params log-level=error "$output_file" 2>&1 | while read -r line; do
    handle_progress "$line" "$ori_duration"
  done

  # 进度条结束
  local output_duration=$(printf "%.3f" $(ffprobe -hide_banner -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$output_file"))
  local formatted_time=$(format_duration $(echo "$output_duration" | bc))

  progress_bar "100.00" "0.00" "0.00" "$formatted_time"

  separator

  # 获取输出文件大小
  local output_size_bytes=$(wc -c <"$output_file" | tr -d ' ')
  local output_size_mb=$(echo "scale=3; $output_size_bytes / 1024 / 1024" | bc)
  printf "%10s %.3f MB → %.3f MB (压缩比: %.2f%%)\n" "体积对比:" "$file_size_mb" "$output_size_mb" "$(echo "scale=2; $output_size_mb / $file_size_mb" | bc)"
  printf "%10s %.2f kbps → %.2f kbps (%.2f%%)\n" "比特率比:" "$original_bitrate_kbps" "$bitrate" "$bitrate_diff_pct"

  local end_time=$(date +%s)
  local elapsed_time=$((end_time - start_time))

  # 人性化时间显示
  if ((elapsed_time < 60)); then
    elapsed_time_str="${elapsed_time}秒"
  elif ((elapsed_time < 3600)); then
    elapsed_time_str="$((elapsed_time / 60))分$((elapsed_time % 60))秒"
  else
    elapsed_time_str="$((elapsed_time / 3600))小时$((elapsed_time % 3600 / 60))分$((elapsed_time % 60))秒"
  fi

  printf "实际耗时: %s\n\r" "$elapsed_time_str"

  printf "%12.12s: %s\n" "输出目录" "$dir_path"
  printf "%12.12s: %s\n" "文件名称" $(basename "${input_file}")

  separator

  # 提示是否打开输出目录
  printf "\033[32m转码完成，是否打开输出目录？\033[0m"
  read -p "[Y/n]" -n 1 -r

  printf "\r$(tput el)" # 换行，避免覆盖
  [[ $REPLY =~ ^[Nn]$ ]] && {
    exit 0
  }

  open -R "$output_file"
  printf "$(tput cuu 1)\r$(tput el)(已打开目录...)\n"
}

# 绘制进度
progress_bar() {

  local current_consuming=$(date +%s)
  local elapsed_consuming_str=$(format_duration $((current_consuming - start_time)))

  # 如果$4没有值，则不显示已转码
  if [[ -z "$4" ]]; then
    printf "\r$(tput cuu 1)$(tput el)已耗时: %.8s | 实时码率: %.2f kbps | 速率: %.2f倍\n" "$elapsed_consuming_str" "$2" "$3"
  else
    printf "\r$(tput cuu 1)$(tput el)已耗时: %.8s | 实时码率: %.2f kbps | 速率: %.2f倍 | 已转码: %s\n" "$elapsed_consuming_str" "$2" "$3" "$4"
  fi

  local bar_length=$(($(tput cols) - 2))

  # 如果$1大于等于100时，则显示完成
  if (($(echo "$1 >= 100" | bc -l))); then
    local filled_length=$(echo "scale=0; ($bar_length) * $1 / 100" | bc)
    local bar=$(printf "%${filled_length}s" | tr ' ' '*')
    # printf "\r$(tput el)[%-${bar_length}s]" "$bar"
    # printf "\n\r$(tput el)"
    printf "\r$(tput el)"
    return
  fi

  local filled_length=$(echo "scale=0; ($bar_length - 7) * $1 / 100" | bc)
  local bar=$(printf "%${filled_length}s" | tr ' ' '*')
  printf "\r$(tput el)[%-$((bar_length - 7))s%6.2f%%]" "$bar" "$1"
}

# 进度处理
handle_progress() {
  local line=$1 total_ms=$(echo "$2 * 1000" | bc)
  # local encoded_bitrate encoding_speed encoding_time_str

  # 获取实时码率
  if [[ "$line" =~ bitrate=[[:space:]]*([0-9.]+)kbits/s ]]; then
    encoded_bitrate=${BASH_REMATCH[1]}
  fi

  if [[ "$line" =~ speed=([0-9.]+)x ]]; then
    encoding_speed=${BASH_REMATCH[1]}
  fi

  # 获取当前时间
  if [[ "$line" =~ out_time=([0-9:.]+) ]]; then
    encoding_time_str=$(echo "${BASH_REMATCH[1]}" | awk -F: '{printf "%02d:%02d:%06.3f", $1, $2, $3}')
  fi

  [[ "$line" =~ out_time_ms=([0-9]+) ]] && {
    local current_ms=$(echo "scale=3; ${BASH_REMATCH[1]} / 1000" | bc)
    local progress=$(echo "scale=5; $current_ms / $total_ms * 100" | bc)
    local bar_length=$(($(tput cols) - 2))
    local filled_length=$(echo "scale=0; ($bar_length * $progress / 100)" | bc)
    local bar=$(printf "%${filled_length}s" | tr ' ' '*')

    progress_bar "$progress" "$encoded_bitrate" "$encoding_speed" "$encoding_time_str"
  }
}

# 清理
cleanup() {
  echo ""
  printf "正在删除临时文件..."
  rm -f "$1"
  printf "\r\033[31m已取消并清理临时文件\033[0m\n"
  exit 1
}

main "$@"
