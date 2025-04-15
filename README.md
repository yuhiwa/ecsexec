# ECSEXEC

ECSEXECは、Amazon ECSのコンテナにSSM経由で簡単に接続するためのコマンドラインツールです。クラスター名、タスクID、コンテナ名からの接続が可能で、Zshのタブ補完機能によりこれらの入力を簡単に行えます。

## 機能

- クラスター名、タスクID、コンテナ名を使用したECSコンテナへの接続
- ローカルキャッシュによる高速な検索
- プロファイルごとのリスト管理
- Zshタブ補完によるクラスター名、タスクID、コンテナ名の簡単入力

## 前提条件

- AWS CLI がインストールされていること
- jq コマンドがインストールされていること (`apt-get install jq` または `brew install jq`)
- AWS Session Manager Plugin がインストールされていること
- ECSタスクでSSM機能が有効になっていること
- Zsh シェルの使用を推奨

## インストール

```bash
# リポジトリをクローン
git clone https://github.com/yuhiwa/ecsexec.git

# スクリプトに実行権限を付与
chmod +x ecsexec/ecsexec.sh

# Zshの設定ファイルに以下を追加
cat << 'EOT' >> ~/.zshrc
# ecsexecコマンドの定義
function ecsexec { ~/ecsexec/ecsexec.sh "$@" }

# Zshの補完関数（1ベースのインデックスを考慮）
_ecsexec() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local profile="default"

  # --profileオプションが指定されている場合、それを取得
  for ((i=1; i <= $#words; i++)); do
    if [[ ${words[i]} == "--profile" && ${words[i+1]} != "" ]]; then
      profile=${words[i+1]}
      break
    fi
  done

  _arguments \
    '1: :->command' \
    '2: :->cluster' \
    '3: :->task' \
    '4: :->container' \
    '--profile[AWS プロファイルを指定]:profiles:_profiles'

  case $state in
    command)
      local commands=(
        'update:ECSリストを更新'
        'remove:キャッシュを削除'
        'connect:ECSコンテナに接続'
      )
      _describe -t commands "command" commands
      ;;
    cluster)
      # 1ベースなので$words[1]はコマンド名、$words[2]が最初の引数（connectなど）
      if [[ $words[2] == "connect" ]]; then
        # すべてのプロファイルのクラスターを収集
        local all_clusters=()
        local clusters_files=(~/.aws_ecs_clusters_*(N))
        
        # 指定されたプロファイルのファイルがあれば優先的に追加
        if [[ -f ~/.aws_ecs_clusters_${profile} ]]; then
          all_clusters+=(${(z)$(cat ~/.aws_ecs_clusters_${profile})})
        fi
        
        # その他のプロファイルのクラスターも追加
        for file in $clusters_files; do
          if [[ $file != ~/.aws_ecs_clusters_${profile} ]]; then
            all_clusters+=(${(z)$(cat $file)})
          fi
        done
        
        # 重複を排除
        typeset -U all_clusters
        _describe -t clusters "cluster" all_clusters
      fi
      ;;
    task)
      if [[ $words[2] == "connect" && -n $words[3] ]]; then
        # すべてのプロファイルのタスクを収集
        local all_tasks=()
        local tasks_files=(~/.aws_ecs_tasks_${words[3]}_*(N))
        
        # 指定されたプロファイルのファイルがあれば優先的に追加
        if [[ -f ~/.aws_ecs_tasks_${words[3]}_${profile} ]]; then
          all_tasks+=(${(z)$(cat ~/.aws_ecs_tasks_${words[3]}_${profile})})
        fi
        
        # その他のプロファイルのタスクも追加
        for file in $tasks_files; do
          if [[ $file != ~/.aws_ecs_tasks_${words[3]}_${profile} ]]; then
            all_tasks+=(${(z)$(cat $file)})
          fi
        done
        
        # 重複を排除
        typeset -U all_tasks
        _describe -t tasks "task" all_tasks
      fi
      ;;
    container)
      if [[ $words[2] == "connect" && -n $words[3] && -n $words[4] ]]; then
        # すべてのプロファイルのコンテナを収集
        local all_containers=()
        local containers_files=(~/.aws_ecs_containers_${words[3]}_${words[4]}_*(N))
        
        # 指定されたプロファイルのファイルがあれば優先的に追加
        if [[ -f ~/.aws_ecs_containers_${words[3]}_${words[4]}_${profile} ]]; then
          all_containers+=(${(z)$(cat ~/.aws_ecs_containers_${words[3]}_${words[4]}_${profile})})
        fi
        
        # その他のプロファイルのコンテナも追加
        for file in $containers_files; do
          if [[ $file != ~/.aws_ecs_containers_${words[3]}_${words[4]}_${profile} ]]; then
            all_containers+=(${(z)$(cat $file)})
          fi
        done
        
        # 重複を排除
        typeset -U all_containers
        _describe -t containers "container" all_containers
      fi
      ;;
  esac
}

# AWS プロファイルの補完
_profiles() {
  local -a profiles
  if [[ -f ~/.aws/credentials ]]; then
    profiles=(${(f)"$(grep '\[' ~/.aws/credentials | sed -e 's/\[//' -e 's/\]//')"})
    _describe -t profiles "AWS profiles" profiles
  fi
}

# 補完関数を登録
compdef _ecsexec ecsexec
EOT

# 設定を反映
source ~/.zshrc
```

## 使用方法

### 初期セットアップ

最初にECS情報を更新して、クラスター、タスク、コンテナのリストを取得します：

```bash
# デフォルトプロファイルのECS情報を更新
ecsexec update

# 特定のプロファイルのECS情報を更新
ecsexec update --profile production
```

### コンテナに接続

```bash
# クラスター名、タスクID、コンテナ名を指定して接続
ecsexec connect my-cluster 1234567890abcdef0 my-container

# 特定のプロファイルを使用して接続
ecsexec connect my-cluster 1234567890abcdef0 my-container --profile production
```

タブ補完を使うと、クラスター名、タスクID、コンテナ名が自動的に補完されます。

### キャッシュの削除

```bash
# デフォルトプロファイルのキャッシュを削除
ecsexec remove

# 特定のプロファイルのキャッシュを削除
ecsexec remove --profile production
```

## 仕組み

1. `update`コマンドを実行すると、ECSのクラスター、タスク、コンテナの情報がローカルにキャッシュされます
2. キャッシュ情報はZshの補完機能で使用され、コマンド入力時に候補が表示されます
3. `connect`コマンドを実行すると、AWS ECS Execute Commandを使ってコンテナにSSM接続します

## 注意事項

- ECSタスクでSSMを使用するには、タスク定義で`enableExecuteCommand`が有効になっている必要があります
- 適切なIAMアクセス許可が設定されている必要があります
- SSM接続には、AWS Session Manager Pluginのインストールが必要です

## トラブルシューティング

- **候補が表示されない場合**: `update`コマンドを実行してキャッシュを更新してください
- **キャッシュに問題がある場合**: `remove`コマンドでキャッシュをクリアしてから`update`を実行してください
- **接続エラーが発生する場合**: ECSタスクでExecute Commandが有効になっているか確認してください
- **コンテナにシェルがない場合**: `/bin/bash`ではなく`/bin/sh`を使うよう`ecsexec.sh`を修正する必要があるかもしれません

## ライセンス

[MITライセンス](LICENSE)
