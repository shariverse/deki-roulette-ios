#!/usr/bin/env ruby
# frozen_string_literal: true

#
# App Store Connect API で、App Store の掲載文とスクリーンショットを登録する。
#
#   1. Bundle ID からアプリを探し、VERSION の App Store バージョンを用意する
#      （無ければ、審査前のバージョンの番号を VERSION に変える。それも無ければ作る）
#   2. 言語（docs/app-store/languages.json）ごとに:
#      - App 情報のローカリゼーションに、アプリ名・サブタイトルを入れる
#      - バージョンのローカリゼーションに、説明文・キーワード・プロモーションテキストを入れる
#      - SCREENSHOT_DIR があれば、画像の寸法から表示サイズを決めて（docs/app-store/screenshots.json）、スクリーンショットを差し替える
#   3. アプリの主要言語を languages.json の先頭の言語にする
#   4. App Review に関する情報のメモに、審査用メモを入れる
#
# 文面は docs/app-store/metadata/<language>.md と review-notes.md の、見出しの下のコードブロックから読む（文面の正はこれら）。
# metadata/<language>.md が無い言語は飛ばす。
# サポート URL・プライバシーポリシー URL・著作権・連絡先・カテゴリ・年齢制限・価格は扱わないので、App Store Connect の画面で入れる。
# 審査への提出は行わない。
#
# 使い方（環境変数で渡す）:
#   BUNDLE_ID=com.basekeita.roulette VERSION=1.1.0 LANGUAGES=ja,en \
#   SCREENSHOT_DIR=build/app-store-screenshots \
#   API_KEY_PATH=AuthKey_XXXXXXXXXX.p8 APPLE_API_KEY_ID=XXXXXXXXXX APPLE_API_ISSUER_ID=xxxxxxxx-... \
#   ruby .github/scripts/app-store-metadata/upload-app-store-metadata.rb
#
# LANGUAGES は登録する言語（カンマ区切り）。空なら languages.json の全言語。
# PLATFORM は登録する App Store バージョンのプラットフォーム（IOS / VISION_OS。既定は IOS）。
# 画像がどのプラットフォームの表示サイズかは screenshots.json の platform から読み、PLATFORM と違うものは飛ばす（iOS と visionOS の取り違えを防ぐ）。
# SCREENSHOT_DIR は scripts/app-store-screenshots.sh の出力先（<表示サイズ>/<言語>/ に画像と manifest.json がある）。
# 空ならスクリーンショットは触らない。撮っていない表示サイズ・言語のスクリーンショットも触らない。透過のある PNG は App Store Connect が受け付けないため、sips で JPEG にしてから上げる（macOS が要る）。
# GITHUB_STEP_SUMMARY が設定されていれば（GitHub Actions 上）、結果を Job Summary にも書き出す。
#
# Ruby の標準ライブラリだけで動く（gem のインストールは不要）。

require 'base64'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'tmpdir'
require 'uri'

API_BASE = 'https://api.appstoreconnect.apple.com'
# 番号を変えたり文面を入れたりできる（審査に出す前・却下後の）バージョンの状態
EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
PROCESSING_TIMEOUT = 15 * 60

# App Store Connect の文字数の上限
LIMITS = { name: 30, subtitle: 30, promotionalText: 170, keywords: 100, description: 4000, notes: 4000 }.freeze

LANGUAGES_PATH = 'docs/app-store/languages.json'
SCREENSHOTS_PATH = 'docs/app-store/screenshots.json'
METADATA_DIR = 'docs/app-store/metadata'

# 登録するプラットフォーム（App Store Connect の値）。screenshots.json の platform（iOS / visionOS）と対応する
PLATFORM = ENV.fetch('PLATFORM', 'IOS')
abort "PLATFORM は IOS か VISION_OS にしてください（#{PLATFORM}）" unless %w[IOS VISION_OS].include?(PLATFORM)
PLATFORM_NAME = { 'IOS' => 'iOS', 'VISION_OS' => 'visionOS' }.fetch(PLATFORM)

def env!(name)
  value = ENV.fetch(name, '')
  abort "環境変数 #{name} が設定されていません" if value.empty?
  value
end

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def summary(markdown)
  puts markdown
  path = ENV.fetch('GITHUB_STEP_SUMMARY', '')
  File.write(path, "#{markdown}\n", mode: 'a') unless path.empty?
end

class ApiError < StandardError
  attr_reader :status

  def initialize(message, status = nil)
    super(message)
    @status = status
  end
end

# App Store Connect API の薄いクライアント。処理待ちで 10 分を超えることがあるため、JWT はリクエストごとに作り直す
class Client
  def initialize(key_path:, key_id:, issuer_id:)
    @key = OpenSSL::PKey::EC.new(File.read(key_path))
    @key_id = key_id
    @issuer_id = issuer_id
  end

  def get(path, query = {})
    request(Net::HTTP::Get, path, query: query)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body: body)
  end

  def patch(path, body)
    request(Net::HTTP::Patch, path, body: body)
  end

  def delete(path)
    request(Net::HTTP::Delete, path)
  end

  private

  # https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
  def token
    now = Time.now.to_i
    header = { alg: 'ES256', kid: @key_id, typ: 'JWT' }
    payload = { iss: @issuer_id, iat: now, exp: now + (10 * 60), aud: 'appstoreconnect-v1' }
    signing_input = "#{base64url(header.to_json)}.#{base64url(payload.to_json)}"
    # OpenSSL の署名は DER 形式なので、JWT が求める r || s（各 32 バイト）に変換する
    der = @key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
    r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\x00") }
    "#{signing_input}.#{base64url(r + s)}"
  end

  def request(klass, path, query: {}, body: nil)
    uri = URI("#{API_BASE}#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?
    req = klass.new(uri)
    req['Authorization'] = "Bearer #{token}"
    if body
      req['Content-Type'] = 'application/json'
      req.body = body.to_json
    end
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(req) }
    # 日本語のメッセージと連結するため、レスポンスは UTF-8 として扱う
    res.body&.force_encoding(Encoding::UTF_8)
    unless res.is_a?(Net::HTTPSuccess)
      raise ApiError.new("#{klass::METHOD} #{path} が失敗しました（HTTP #{res.code}）\n#{res.body}", res.code.to_i)
    end

    res.body.to_s.empty? ? {} : JSON.parse(res.body)
  end
end

# Markdown の「## <見出し>」の下にある最初のコードブロックの中身を返す。見出しが nil なら、ファイルの最初のコードブロック
def code_block(markdown, heading = nil)
  lines = markdown.lines
  start = heading ? lines.index { |l| l.start_with?("## #{heading}") } : -1
  abort "見出し「#{heading}」が見つかりません" unless start
  open = (start + 1...lines.size).find { |i| lines[i].start_with?('```') }
  abort "見出し「#{heading}」の下にコードブロックがありません" unless open
  close = (open + 1...lines.size).find { |i| lines[i].start_with?('```') }
  abort "見出し「#{heading}」のコードブロックが閉じていません" unless close
  lines[(open + 1)...close].join.strip
end

def check_limits(texts, label)
  over = texts.select { |key, value| value.length > LIMITS.fetch(key) }
  return if over.empty?

  abort over.map { |key, value| "#{label}: #{key} が #{value.length} 文字です（上限 #{LIMITS[key]} 文字）" }.join("\n")
end

# 言語の掲載文。ファイルが無ければ nil
def read_listing(language)
  path = File.join(METADATA_DIR, "#{language}.md")
  return nil unless File.exist?(path)

  listing = File.read(path, encoding: Encoding::UTF_8)
  texts = {
    name: code_block(listing, 'アプリ名'),
    subtitle: code_block(listing, 'サブタイトル'),
    promotionalText: code_block(listing, 'プロモーションテキスト'),
    description: code_block(listing, '説明文'),
    keywords: code_block(listing, 'キーワード')
  }
  check_limits(texts, path)
  texts
end

# languages.json の言語のうち、LANGUAGES で指定したもの（空なら全部）
def select_languages(wanted)
  languages = JSON.parse(File.read(LANGUAGES_PATH, encoding: Encoding::UTF_8)).fetch('languages')
  return languages if wanted.empty?

  unknown = wanted - languages.map { |l| l['language'] }
  abort "#{LANGUAGES_PATH} に無い言語です: #{unknown.join(', ')}" unless unknown.empty?
  languages.select { |l| wanted.include?(l['language']) }
end

# 画像の寸法（縦向き）→ [表示サイズ, プラットフォーム]。screenshots.json の sizes から作る
def display_types_by_size
  JSON.parse(File.read(SCREENSHOTS_PATH, encoding: Encoding::UTF_8)).fetch('displayTypes').each_with_object({}) do |(type, spec), table|
    spec.fetch('sizes').each { |size| table[size.split('x').map(&:to_i)] = [type, spec.fetch('platform', 'iOS')] }
  end
end

def find_app(client, bundle_id)
  data = client.get('/v1/apps', 'filter[bundleId]' => bundle_id, 'fields[apps]' => 'name,bundleId,primaryLocale').fetch('data')
  # filter が完全一致でない場合に備えて、Bundle ID が一致するものだけを見る
  data.find { |app| app.dig('attributes', 'bundleId') == bundle_id }
end

def version_state(version)
  version.dig('attributes', 'appVersionState') || version.dig('attributes', 'appStoreState')
end

# ログ用に「1.0.0（PREPARE_FOR_SUBMISSION）」の形で並べる
def version_list_text(versions)
  versions.map { |v| "#{v.dig('attributes', 'versionString')}（#{version_state(v)}）" }.join('、')
end

# VERSION の App Store バージョン（platform）を返す。無ければ審査前のものの番号を変え、それも無ければ作る
def prepare_version(client, app_id, version_string, platform)
  versions = client.get(
    "/v1/apps/#{app_id}/appStoreVersions",
    'filter[platform]' => platform,
    'fields[appStoreVersions]' => 'versionString,appVersionState,appStoreState',
    'limit' => '20'
  ).fetch('data')

  version = versions.find { |v| v.dig('attributes', 'versionString') == version_string }
  if version
    state = version_state(version)
    unless EDITABLE_STATES.include?(state)
      abort "::error::バージョン #{version_string}（#{platform}）は編集できない状態です（#{state}）。今あるバージョン: #{versions.empty? ? 'なし' : version_list_text(versions)}"
    end
    return [version, 'そのまま使いました']
  end

  editable = versions.find { |v| EDITABLE_STATES.include?(version_state(v)) }
  if editable
    old = editable.dig('attributes', 'versionString')
    updated = client.patch("/v1/appStoreVersions/#{editable['id']}", {
      data: { type: 'appStoreVersions', id: editable['id'], attributes: { versionString: version_string } }
    }).fetch('data')
    return [updated, "審査前のバージョン #{old} の番号を変えました"]
  end

  created = begin
    client.post('/v1/appStoreVersions', {
      data: {
        type: 'appStoreVersions',
        attributes: { platform: platform, versionString: version_string },
        relationships: { app: { data: { type: 'apps', id: app_id } } }
      }
    }).fetch('data')
  rescue ApiError => e
    # 「今の状態では新しいバージョンを作れない」ときは、審査中のバージョンがあるなど、画面を開かないと分からないことが多い
    abort "::error::バージョン #{version_string}（#{platform}）を作れませんでした（#{e.message.lines.first.strip}）。今あるバージョン: #{versions.empty? ? 'なし' : version_list_text(versions)}"
  end
  [created, '新しく作りました']
end

# 審査前の App 情報（アプリ名・サブタイトルを持つ）を返す。一緒に、今ある App 情報の状態も返す（失敗したときの手がかり用）
def editable_app_info(client, app_id)
  infos = client.get("/v1/apps/#{app_id}/appInfos").fetch('data')
  state_of = ->(i) { i.dig('attributes', 'state') || i.dig('attributes', 'appStoreState') }
  editable = infos.find { |i| EDITABLE_STATES.include?(state_of.call(i)) }
  [editable, infos.map { |i| state_of.call(i) }.join('、')]
end

# ローカリゼーションを locale で探し、あれば更新・無ければ作る
def upsert_localization(client, list_path:, type:, parent_key:, parent_type:, parent_id:, locale:, attributes:)
  existing = client.get(list_path, "fields[#{type}]" => 'locale').fetch('data').find { |l| l.dig('attributes', 'locale') == locale }
  if existing
    client.patch("/v1/#{type}/#{existing['id']}", { data: { type: type, id: existing['id'], attributes: attributes } })
    [existing['id'], '更新']
  else
    created = client.post("/v1/#{type}", {
      data: {
        type: type,
        attributes: attributes.merge(locale: locale),
        relationships: { parent_key => { data: { type: parent_type, id: parent_id } } }
      }
    }).fetch('data')
    [created['id'], '作成']
  end
end

def upsert_review_notes(client, version_id, notes)
  attributes = { notes: notes, demoAccountRequired: false }
  detail = begin
    client.get("/v1/appStoreVersions/#{version_id}/appStoreReviewDetail").fetch('data')
  rescue ApiError => e
    raise unless e.status == 404

    nil
  end

  if detail
    return '変更なし' if detail.dig('attributes', 'notes') == notes

    begin
      client.patch("/v1/appStoreReviewDetails/#{detail['id']}", { data: { type: 'appStoreReviewDetails', id: detail['id'], attributes: attributes } })
    rescue ApiError => e
      # 一度作った後の更新では、連絡先（氏名・電話・メール）が未入力だと 409 で弾かれる。連絡先は画面で入れるので、警告にとどめる
      raise unless e.status == 409

      puts "::warning::審査用メモを更新できませんでした。App Review の連絡先を画面で入れてから再実行してください"
      return '失敗（連絡先が未入力）'
    end
    '更新'
  else
    client.post('/v1/appStoreReviewDetails', {
      data: {
        type: 'appStoreReviewDetails',
        attributes: attributes,
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } } }
      }
    })
    '作成'
  end
end

# PNG の幅・高さと透過の有無を IHDR から読む
def png_info(path)
  header = File.binread(path, 26)
  abort "#{path} は PNG ではありません" unless header&.start_with?("\x89PNG".b)
  width, height = header.byteslice(16, 8).unpack('NN')
  color_type = header.getbyte(25)
  { width: width, height: height, alpha: [4, 6].include?(color_type) }
end

# scripts/app-store-screenshots.sh の出力から、ある言語の画像を、表示サイズごとに撮った順に集める
def collect_screenshots(screenshot_dir, language, work_dir)
  types = display_types_by_size
  groups = Hash.new { |h, k| h[k] = [] }
  Dir.glob(File.join(screenshot_dir, '*', language)).sort.each do |device_dir|
    next unless File.directory?(device_dir)

    files =
      if File.exist?(File.join(device_dir, 'manifest.json'))
        # iOS（XCTest の添付）は、書き出したファイル名が UUID なので、添付の名前（「01-ホーム_0_…」）の順に並べる
        attachments = JSON.parse(File.read(File.join(device_dir, 'manifest.json'), encoding: Encoding::UTF_8))
                          .flat_map { |test| test.fetch('attachments') }
        attachments.sort_by { |a| a.fetch('suggestedHumanReadableName') }.map { |a| a.fetch('exportedFileName') }
      else
        # visionOS はホスト（scripts/app-store-screenshots.sh）が simctl で直接撮るので、添付がなくファイル名の順に並べる
        Dir.children(device_dir).select { |file| file.end_with?('.png') }.sort
      end
    files.each do |file|
      path = File.join(device_dir, file)
      info = png_info(path)
      type, platform = types[[info[:width], info[:height]]]
      abort "#{path} のサイズ（#{info[:width]}x#{info[:height]}）に合う表示サイズが #{SCREENSHOTS_PATH} にありません" unless type
      # 別のプラットフォームの表示サイズ（iOS と visionOS の取り違え）は、この実行では触らない
      next unless platform == PLATFORM_NAME

      if info[:alpha]
        jpeg = File.join(work_dir, "#{language}-#{File.basename(file, '.*')}.jpg")
        system('sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '95', path, '--out', jpeg, out: File::NULL, exception: true)
        path = jpeg
      end
      groups[type] << path
    end
  end
  groups
end

def upload_screenshot(client, set_id, path)
  file_name = File.basename(path)
  bytes = File.binread(path)
  reservation = client.post('/v1/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: file_name, fileSize: bytes.bytesize },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set_id } } }
    }
  }).fetch('data')
  screenshot_id = reservation['id']

  # アップロード先の URL は認証不要・期限付きのため、JWT は付けない
  reservation.dig('attributes', 'uploadOperations').each do |op|
    uri = URI(op['url'])
    req = Net::HTTPGenericRequest.new(op['method'], true, true, uri)
    op['requestHeaders'].each { |h| req[h['name']] = h['value'] }
    req.body = bytes.byteslice(op['offset'], op['length'])
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    raise ApiError, "#{file_name} のアップロードに失敗しました（HTTP #{res.code}）\n#{res.body}" unless res.is_a?(Net::HTTPSuccess)
  end

  client.patch("/v1/appScreenshots/#{screenshot_id}", {
    data: { type: 'appScreenshots', id: screenshot_id, attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } }
  })
  puts "アップロードしました: #{file_name}（#{screenshot_id}）"
  screenshot_id
end

def wait_screenshots(client, ids)
  deadline = Time.now + PROCESSING_TIMEOUT
  pending = ids.dup
  results = {}
  until pending.empty?
    pending.reject! do |id|
      delivery = client.get("/v1/appScreenshots/#{id}", 'fields[appScreenshots]' => 'fileName,assetDeliveryState').dig('data', 'attributes')
      state = delivery.dig('assetDeliveryState', 'state')
      next false if %w[AWAITING_UPLOAD UPLOAD_COMPLETE].include?(state)

      results[id] = [delivery['fileName'], state, delivery.dig('assetDeliveryState', 'errors')]
      true
    end
    break if pending.empty?
    raise ApiError, "スクリーンショットの処理が #{PROCESSING_TIMEOUT / 60} 分で終わりませんでした" if Time.now > deadline

    sleep 10
  end
  results
end

# 種類ごとに、既存のスクリーンショットを消してから撮った順に上げ直す
def replace_screenshots(client, localization_id, groups, locale)
  sets = client.get(
    "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets",
    'fields[appScreenshotSets]' => 'screenshotDisplayType'
  ).fetch('data')

  rows = []
  groups.each do |type, paths|
    set = sets.find { |s| s.dig('attributes', 'screenshotDisplayType') == type }
    set ||= client.post('/v1/appScreenshotSets', {
      data: {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: type },
        relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: localization_id } } }
      }
    }).fetch('data')

    existing = client.get("/v1/appScreenshotSets/#{set['id']}/appScreenshots", 'fields[appScreenshots]' => 'fileName').fetch('data')
    existing.each { |s| client.delete("/v1/appScreenshots/#{s['id']}") }

    ids = paths.map { |path| upload_screenshot(client, set['id'], path) }
    results = wait_screenshots(client, ids)
    # 上げた順に並べる
    client.patch("/v1/appScreenshotSets/#{set['id']}/relationships/appScreenshots", { data: ids.map { |id| { type: 'appScreenshots', id: id } } })

    ids.each do |id|
      file_name, state, errors = results[id]
      details = errors && !errors.empty? ? "<br>#{errors.to_json}" : ''
      rows << "| #{type} | #{file_name} | #{state}#{details} |"
    end
    rows << "| #{type} | （既存の #{existing.size} 枚を削除） | |" unless existing.empty?
  end

  summary(<<~MARKDOWN)
    ### スクリーンショット（#{locale}）

    | 種類 | ファイル | 状態 |
    | --- | --- | --- |
    #{rows.join("\n")}
  MARKDOWN
  rows.none? { |r| r.include?('FAILED') }
end

bundle_id = env!('BUNDLE_ID')
version_string = env!('VERSION')
review_notes_path = ENV.fetch('REVIEW_NOTES_PATH', 'docs/app-store/review-notes.md')
screenshot_dir = ENV.fetch('SCREENSHOT_DIR', '')
languages = select_languages(ENV.fetch('LANGUAGES', '').split(',').map(&:strip).reject(&:empty?))

# 文字数の上限は、何かを登録する前に全言語ぶん確かめる
listings = languages.to_h { |l| [l['language'], read_listing(l['language'])] }
notes = code_block(File.read(review_notes_path, encoding: Encoding::UTF_8))
check_limits({ notes: notes }, review_notes_path)
client = Client.new(key_path: env!('API_KEY_PATH'), key_id: env!('APPLE_API_KEY_ID'), issuer_id: env!('APPLE_API_ISSUER_ID'))

begin
  summary("## App Store の掲載文とスクリーンショットの登録（#{bundle_id} #{version_string}・#{PLATFORM}）\n")

  app = find_app(client, bundle_id)
  unless app
    summary("Bundle ID `#{bundle_id}` のアプリが App Store Connect にありません。先に Web 画面でアプリを作成してください。")
    puts "::error::App Store Connect に #{bundle_id} のアプリがありません"
    exit 1
  end
  summary("アプリ: #{app.dig('attributes', 'name')}（ID: `#{app['id']}`、主要言語: #{app.dig('attributes', 'primaryLocale')}）\n")

  version, how = prepare_version(client, app['id'], version_string, PLATFORM)
  summary("バージョン #{version_string}（#{PLATFORM}）: #{how}（ID: `#{version['id']}`）\n")

  app_info, app_info_states = editable_app_info(client, app['id'])
  abort "::error::編集できる（審査前の）App 情報がありません（今ある App 情報の状態: #{app_info_states.empty? ? 'なし' : app_info_states}）" unless app_info

  rows = []
  screenshots_ok = true
  Dir.mktmpdir do |work_dir|
    languages.each do |language|
      code = language['language']
      locale = language['storeLocale']
      texts = listings[code]
      unless texts
        rows << "| #{locale} | （#{METADATA_DIR}/#{code}.md が無いので飛ばしました） | |"
        puts "::warning::#{code} の掲載文が無いので飛ばします"
        next
      end

      _, info_done = upsert_localization(
        client,
        list_path: "/v1/appInfos/#{app_info['id']}/appInfoLocalizations",
        type: 'appInfoLocalizations', parent_key: :appInfo, parent_type: 'appInfos', parent_id: app_info['id'],
        locale: locale, attributes: texts.slice(:name, :subtitle)
      )
      localization_id, version_done = upsert_localization(
        client,
        list_path: "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations",
        type: 'appStoreVersionLocalizations', parent_key: :appStoreVersion, parent_type: 'appStoreVersions', parent_id: version['id'],
        locale: locale, attributes: texts.slice(:description, :keywords, :promotionalText)
      )
      rows << "| #{locale} | #{texts[:name]} | App 情報: #{info_done} / バージョン: #{version_done} |"

      next if screenshot_dir.empty?

      groups = collect_screenshots(screenshot_dir, code, work_dir)
      screenshots_ok &= replace_screenshots(client, localization_id, groups, locale) unless groups.empty?
    end
  end

  done = upsert_review_notes(client, version['id'], notes)
  rows << "| （共通） | App Review に関する情報のメモ（デモ用アカウントは不要） | #{done} |"

  # 主要言語は、そのローカリゼーションができてから変える
  primary = languages.first
  if primary && listings[primary['language']] && app.dig('attributes', 'primaryLocale') != primary['storeLocale']
    begin
      client.patch("/v1/apps/#{app['id']}", { data: { type: 'apps', id: app['id'], attributes: { primaryLocale: primary['storeLocale'] } } })
      rows << "| （共通） | 主要言語を #{primary['storeLocale']} に変更 | 更新 |"
    rescue ApiError => e
      rows << "| （共通） | 主要言語を #{primary['storeLocale']} に変更 | 失敗（画面で変えてください） |"
      puts "::warning::主要言語を変えられませんでした: #{e.message.lines.first.strip}"
    end
  end

  summary(<<~MARKDOWN)
    ### 掲載文

    | ロケール | アプリ名・項目 | 結果 |
    | --- | --- | --- |
    #{rows.join("\n")}
  MARKDOWN
  summary("スクリーンショットは触っていません（SCREENSHOT_DIR が空）。\n") if screenshot_dir.empty?

  summary(<<~MARKDOWN)
    ### 画面で入れるもの

    サポート URL・プライバシーポリシー URL・著作権・App Review の連絡先・カテゴリ・年齢制限・価格と配信国・App のプライバシー・ビルドの選択は、このスクリプトでは入れていません。審査に出す前に App Store Connect の画面で入れてください。
  MARKDOWN
  exit 1 unless screenshots_ok
rescue ApiError => e
  summary("### エラー\n\n```\n#{e.message}\n```\n")
  puts "::error::#{e.message.lines.first.strip}"
  exit 1
end
