#!/usr/bin/env ruby
# frozen_string_literal: true

# 消除 CocoaPods 为 Runner 生成的 Embed / Copy Resources 中「同一产物路径出现两次」的问题，
# 修复 Xcode 15+：Multiple commands produce ... NIMSDK.framework / Assets.car
#
# 用法：
#   ruby dedupe_cocoapods_embed.rb [Pods 目录]
# 未传参时默认：本脚本所在目录下的 Pods（即 im_demo/ios/Pods）

def dedupe_key_for_output(out_line)
  o = out_line.strip
  return o if o.empty?

  # 取路径最后一段（兼容 $(VAR)/path 形式）
  tail = o.split(%r{[/\\]}).last.to_s
  tail = tail.gsub(/["'`]/, '')
  base = File.basename(tail)
  return base if base.end_with?('.framework')
  return 'Assets.car' if base == 'Assets.car'

  o
end

def dedupe_xcfilelists(support)
  %w[frameworks resources].each do |kind|
    %w[Debug Release Profile].each do |cfg|
      inf = File.join(support, "Pods-Runner-#{kind}-#{cfg}-input-files.xcfilelist")
      outf = File.join(support, "Pods-Runner-#{kind}-#{cfg}-output-files.xcfilelist")
      next unless File.exist?(inf) && File.exist?(outf)

      ins = File.readlines(inf).map(&:strip).reject(&:empty?)
      outs = File.readlines(outf).map(&:strip).reject(&:empty?)
      next if ins.length != outs.length

      seen = {}
      new_in = []
      new_out = []
      ins.zip(outs).each do |i_line, o_line|
        key = dedupe_key_for_output(o_line)
        next if seen[key]

        seen[key] = true
        new_in << i_line
        new_out << o_line
      end
      File.write(inf, new_in.join("\n") + "\n")
      File.write(outf, new_out.join("\n") + "\n")
    end
  end
end

pods_root = ARGV[0] ? File.expand_path(ARGV[0]) : File.join(__dir__, 'Pods')
support = File.join(pods_root, 'Target Support Files', 'Pods-Runner')

unless Dir.exist?(support)
  warn "[dedupe_cocoapods_embed] skip: #{support} not found"
  exit 0
end

dedupe_xcfilelists(support)
puts "[dedupe_cocoapods_embed] ok: #{support}"
