# frozen_string_literal: true
#
# ios-resign 設定讀取器：讀 resign.yaml（進版控）＋同資料夾的 resign.local.yaml（本機），
# 本機逐層蓋過專案設定，選定版本後輸出 shell 變數給 resign.sh 用 eval 讀。
#
#   ruby config.rb env  <resign.yaml> [版本]   # 輸出 RESIGN_* 變數
#   ruby config.rb list <resign.yaml>          # 給人／agent 看的摘要
#
# 只用 macOS 內建 Ruby 的標準函式庫。所有值一律當字串（直接取 YAML 原始字面），
# 避開 YAML 自動猜型別：1.10 變 1.1、no 變 false、00012 變 12。
# 錯誤印到 stderr 並以 2 結束，resign.sh 會轉成結束碼 10。

require "psych"
require "shellwords"

def die(msg)
  warn "✖ #{msg}"
  exit 2
end

# 把 YAML 語法樹轉成 Hash／Array／String，純量一律取原始字串
def to_plain(node)
  case node
  when Psych::Nodes::Document then to_plain(node.root)
  when Psych::Nodes::Mapping
    node.children.each_slice(2).each_with_object({}) { |(k, v), h| h[k.value.to_s] = to_plain(v) }
  when Psych::Nodes::Sequence then node.children.map { |c| to_plain(c) }
  when Psych::Nodes::Scalar then node.value.to_s
  when Psych::Nodes::Alias then die("不支援 YAML 別名（&／*），請直接寫出值")
  when nil then nil
  else die("看不懂的 YAML 結構：#{node.class}")
  end
end

def load_yaml(path)
  return {} unless File.exist?(path)
  doc = Psych.parse(File.read(path, encoding: "UTF-8"), filename: path)
  data = doc ? to_plain(doc) : {}
  data ||= {}
  die("#{path} 最外層要是 key: value 的對應表") unless data.is_a?(Hash)
  data
rescue Psych::SyntaxError => e
  die("#{path} 的 YAML 寫錯：#{e.message}")
end

# 本機設定逐層蓋過專案設定；陣列（例如 devices）整個取代，不合併
def deep_merge(base, over)
  return over unless base.is_a?(Hash) && over.is_a?(Hash)
  base.merge(over) { |_, a, b| deep_merge(a, b) }
end

# macOS 內建的是 Ruby 2.6，別用 3.x 才有的語法
def blank?(v)
  v.nil? || (v.is_a?(String) && v.strip.empty?)
end

mode, cfg_path, want_variant = ARGV
die("用法：ruby config.rb env|list <resign.yaml> [版本]") unless %w[env list].include?(mode) && cfg_path
die("找不到設定檔 #{cfg_path}") unless File.exist?(cfg_path)

root = File.dirname(File.expand_path(cfg_path))
local_path = File.join(root, "resign.local.yaml")
project_cfg = load_yaml(cfg_path)
die("resign.yaml 不該寫 devices（手機跟著電腦走，寫在 resign.local.yaml）") if project_cfg.key?("devices")
cfg = deep_merge(project_cfg, load_yaml(local_path))

die("resign.yaml 缺 project（Xcode 專案路徑，相對於 resign.yaml 所在資料夾）") if blank?(cfg["project"])
project = File.expand_path(cfg["project"], root)
die("找不到 Xcode 專案：#{project}") unless File.directory?(project)
variants = cfg["variants"]
die("resign.yaml 缺 variants（至少一個版本，含 scheme 與 bundle_id）") unless variants.is_a?(Hash) && !variants.empty?
variants.each do |vn, v|
  die("版本 #{vn} 要是對應表") unless v.is_a?(Hash)
  %w[scheme bundle_id].each { |k| die("版本 #{vn} 缺 #{k}") if blank?(v[k]) }
end

# 覆蓋 bundle ID 時要設的建置變數。預設 PRODUCT_BUNDLE_IDENTIFIER；
# 專案有 App 擴充功能（小工具、即時動態）時，命令列的值會套到所有 target 而撞名，
# 那種專案讓各 target 從同一個自訂變數推出 bundle ID（例如擴充功能＝$(變數).widget），這裡寫那個變數名
bundle_setting = blank?(cfg["bundle_id_setting"]) ? "PRODUCT_BUNDLE_IDENTIFIER" : cfg["bundle_id_setting"]
die("bundle_id_setting 要是建置變數名稱（大寫英文、數字、底線），現在是：#{bundle_setting}") unless bundle_setting =~ /\A[A-Z_][A-Z0-9_]*\z/

devices = cfg["devices"] || []
die("resign.local.yaml 的 devices 要是清單") unless devices.is_a?(Array)
devices.each_with_index do |d, i|
  die("devices 第 #{i + 1} 筆要有 name 與 udid") unless d.is_a?(Hash) && !blank?(d["name"]) && !blank?(d["udid"])
end

if mode == "list"
  puts "名稱：#{cfg['name'] || File.basename(root)}"
  puts "Xcode 專案：#{project}"
  puts "團隊：#{blank?(cfg['team']) ? '（未設定，用專案檔裡的）' : cfg['team']}"
  puts "預設版本：#{cfg['default_variant'] || (variants.size == 1 ? variants.keys.first : '（未設定）')}"
  variants.each { |vn, v| puts "  版本 #{vn}：scheme #{v['scheme']}，bundle ID #{v['bundle_id']}#{v['label'] ? "（#{v['label']}）" : ''}" }
  puts "覆蓋 bundle ID 用的變數：#{bundle_setting}" unless bundle_setting == "PRODUCT_BUNDLE_IDENTIFIER"
  puts "建置前指令：#{cfg['prebuild'] || '無'}"
  puts(devices.empty? ? "手機：本機設定沒有列任何手機（只能 --build-only）" : "手機：#{devices.map { |d| "#{d['name']}（#{d['udid']}）" }.join('、')}")
  exit 0
end

variant = want_variant
variant = cfg["default_variant"] if blank?(variant)
variant = variants.keys.first if blank?(variant) && variants.size == 1
die("有好幾個版本（#{variants.keys.join('、')}），要指定 --variant 或在設定寫 default_variant") if blank?(variant)
die("沒有叫「#{variant}」的版本，可用：#{variants.keys.join('、')}") unless variants.key?(variant)
v = variants[variant]

out = {
  "RESIGN_NAME" => cfg["name"] || File.basename(root),
  "RESIGN_ROOT" => root,
  "RESIGN_PROJECT" => project,
  "RESIGN_TEAM" => cfg["team"] || "",
  "RESIGN_VARIANT" => variant,
  "RESIGN_SCHEME" => v["scheme"],
  "RESIGN_BUNDLE_ID" => v["bundle_id"],
  "RESIGN_CONFIGURATION" => v["configuration"] || cfg["configuration"] || "Debug",
  "RESIGN_PREBUILD" => cfg["prebuild"] || "",
  # 本機設定刻意改了這個版本的 bundle ID（分享出去各簽各的）才從命令列覆蓋
  "RESIGN_BUNDLE_OVERRIDE" => (((project_cfg["variants"] || {})[variant] || {})["bundle_id"] != v["bundle_id"]) ? "1" : "0",
  "RESIGN_BUNDLE_SETTING" => bundle_setting,
  "RESIGN_ALLOW_PAID_TEAM" => cfg["allow_paid_team"] == "true" ? "1" : "0",
  "RESIGN_DEVICE_COUNT" => devices.size.to_s,
}
devices.each_with_index do |d, i|
  out["RESIGN_DEVICE_NAME_#{i}"] = d["name"]
  out["RESIGN_DEVICE_UDID_#{i}"] = d["udid"]
end
out.each { |k, val| puts "#{k}=#{Shellwords.escape(val.to_s)}" }
