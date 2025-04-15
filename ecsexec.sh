#!/bin/bash

# ecsexec.sh - ECSタスクにSSM経由で接続するBashスクリプト

# 設定ファイルのパスを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# キャッシュファイルの読み込み
get_clusters() {
    local profile=$1
    local cache_file="${SCRIPT_DIR}/${profile}_clusters.cache"
    
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        update_clusters "$profile"
        cat "$cache_file"
    fi
}

# クラスターのキャッシュを更新
update_clusters() {
    local profile=$1
    local cache_file="${SCRIPT_DIR}/${profile}_clusters.cache"
    
    # AWS CLI の出力を明示的に JSON 形式に指定
    aws ecs list-clusters --profile "$profile" --output json > "$cache_file"
    echo "クラスター情報を更新しました"
}

# タスクのキャッシュを読み込み
get_tasks() {
    local cluster=$1
    local profile=$2
    local cache_file="${SCRIPT_DIR}/${profile}_${cluster}_tasks.cache"
    
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        update_tasks "$cluster" "$profile"
        cat "$cache_file"
    fi
}

# タスクのキャッシュを更新
update_tasks() {
    local cluster=$1
    local profile=$2
    local cache_file="${SCRIPT_DIR}/${profile}_${cluster}_tasks.cache"
    
    # AWS CLI の出力を明示的に JSON 形式に指定
    aws ecs list-tasks --cluster "$cluster" --profile "$profile" --output json > "$cache_file"
    echo "タスク情報を更新しました"
}

# コンテナのキャッシュを読み込み
get_containers() {
    local cluster=$1
    local task=$2
    local profile=$3
    local cache_file="${SCRIPT_DIR}/${profile}_${cluster}_${task}_containers.cache"
    
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        update_containers "$cluster" "$task" "$profile"
        cat "$cache_file"
    fi
}

# コンテナのキャッシュを更新
update_containers() {
    local cluster=$1
    local task=$2
    local profile=$3
    local cache_file="${SCRIPT_DIR}/${profile}_${cluster}_${task}_containers.cache"
    
    # AWS CLI の出力を明示的に JSON 形式に指定
    aws ecs describe-tasks --cluster "$cluster" --tasks "$task" --profile "$profile" --output json > "$cache_file"
    echo "コンテナ情報を更新しました"
}

# キャッシュを削除
remove_cache() {
    local profile=$1
    
    # キャッシュディレクトリのファイルを削除
    local cache_files=($(ls -1 "${SCRIPT_DIR}/${profile}"*.cache 2>/dev/null))
    
    if [ ${#cache_files[@]} -eq 0 ]; then
        echo "キャッシュファイルが見つかりません"
    else
        rm -f "${cache_files[@]}"
        echo "キャッシュファイルを削除しました:"
        printf "%s\n" "${cache_files[@]}"
    fi
    
    # ホームディレクトリの補完用ファイルを削除
    rm -f "$HOME/.aws_ecs_clusters_$profile" 2>/dev/null
    echo "クラスターリストファイルを削除しました"
    
    rm -f "$HOME/.aws_ecs_tasks_"*"_$profile" 2>/dev/null
    echo "タスクリストファイルを削除しました"
    
    rm -f "$HOME/.aws_ecs_containers_"*"_$profile" 2>/dev/null
    echo "コンテナリストファイルを削除しました"
}

# クラスターリストを取得
get_cluster_list() {
    local profile=$1
    local cache_data=$(get_clusters "$profile")
    
    # jqを使ってすべてのクラスター名を抽出（エラーハンドリング追加）
    if ! echo "$cache_data" | jq -e . > /dev/null 2>&1; then
        echo "キャッシュファイルの形式が正しくありません。update-clusters コマンドを実行してキャッシュを更新してください。" >&2
        # 失敗してもエラーを返さず空の結果を返す
        return 0
    fi
    
    # クラスター名のみを抽出
    echo "$cache_data" | jq -r '.clusterArns[] | split("/") | .[-1]' | sort
}

# タスクリストを取得
get_task_list() {
    local cluster=$1
    local profile=$2
    local cache_data=$(get_tasks "$cluster" "$profile")
    
    # jqを使ってすべてのタスクARNを抽出（エラーハンドリング追加）
    if ! echo "$cache_data" | jq -e . > /dev/null 2>&1; then
        echo "タスクキャッシュファイルの形式が正しくありません。" >&2
        # 失敗してもエラーを返さず空の結果を返す
        return 0
    fi
    
    # タスクIDのみを抽出
    echo "$cache_data" | jq -r '.taskArns[] | split("/") | .[-1]' | sort
}

# コンテナリストを取得
get_container_list() {
    local cluster=$1
    local task=$2
    local profile=$3
    local cache_data=$(get_containers "$cluster" "$task" "$profile")
    
    # jqを使ってすべてのコンテナ名を抽出（エラーハンドリング追加）
    if ! echo "$cache_data" | jq -e . > /dev/null 2>&1; then
        echo "コンテナキャッシュファイルの形式が正しくありません。" >&2
        # 失敗してもエラーを返さず空の結果を返す
        return 0
    fi
    
    # コンテナ名のみを抽出
    echo "$cache_data" | jq -r '.tasks[0].containers[].name' | sort
}

# キャッシュを更新してリストを生成
update_ecs_lists() {
    local profile=$1
    
    echo "クラスター情報を更新中..."
    # 強制的にクラスター情報を更新
    update_clusters "$profile"
    
    local cluster_list=$(get_cluster_list "$profile")
    if [ -z "$cluster_list" ]; then
        echo "クラスター情報の取得中にエラーが発生しましたが、処理を続行します。"
    fi
    
    # クラスターリストをファイルに保存
    local clusters_file="$HOME/.aws_ecs_clusters_$profile"
    echo "$cluster_list" | tr '\n' ' ' > "$clusters_file"
    echo " " >> "$clusters_file"  # 末尾にスペースを追加
    echo "クラスターリストを $clusters_file に保存しました"
    
    # 各クラスターのタスクを更新
    for cluster in $cluster_list; do
        echo "クラスター $cluster のタスク情報を更新中..."
        # 強制的にタスク情報を更新
        update_tasks "$cluster" "$profile"
        
        local task_list=$(get_task_list "$cluster" "$profile")
        if [ -z "$task_list" ]; then
            echo "タスク情報が見つかりませんが、処理を続行します。"
            continue
        fi
        
        # タスクリストをファイルに保存
        local tasks_file="$HOME/.aws_ecs_tasks_${cluster}_$profile"
        echo "$task_list" | tr '\n' ' ' > "$tasks_file"
        echo " " >> "$tasks_file"  # 末尾にスペースを追加
        echo "タスクリストを $tasks_file に保存しました"
        
        # 各タスクのコンテナを更新
        for task in $task_list; do
            echo "タスク $task のコンテナ情報を更新中..."
            # 強制的にコンテナ情報を更新
            update_containers "$cluster" "$task" "$profile"
            
            local container_list=$(get_container_list "$cluster" "$task" "$profile")
            if [ -z "$container_list" ]; then
                echo "コンテナ情報が見つかりませんが、処理を続行します。"
                continue
            fi
            
            # コンテナリストをファイルに保存
            local containers_file="$HOME/.aws_ecs_containers_${cluster}_${task}_$profile"
            echo "$container_list" | tr '\n' ' ' > "$containers_file"
            echo " " >> "$containers_file"  # 末尾にスペースを追加
            echo "コンテナリストを $containers_file に保存しました"
        done
    done
    
    echo "すべてのECS情報を更新しました。"
    return 0
}

# コンテナにSSMでログインする
ecs_execute_command() {
    local cluster=$1
    local task=$2
    local container=$3
    local profile=$4
    
    echo "接続中: クラスター: $cluster, タスク: $task, コンテナ: $container"
    aws ecs execute-command \
        --cluster "$cluster" \
        --task "$task" \
        --container "$container" \
        --interactive \
        --command "/bin/bash" \
        --profile "$profile"
}

# メイン処理
main() {
    local action=""
    local cluster=""
    local task=""
    local container=""
    local profile="default"
    
    # 引数解析
    if [ $# -lt 1 ]; then
        echo "使用法: $0 [update|remove|connect] [--profile PROFILE]"
        echo "        $0 connect CLUSTER TASK CONTAINER [--profile PROFILE]"
        exit 1
    fi
    
    action=$1
    shift
    
    # アクションに応じて引数を解析
    if [ "$action" = "connect" ]; then
        if [ $# -lt 3 ]; then
            echo "接続には、クラスター名、タスクID、コンテナ名が必要です。"
            echo "使用法: $0 connect CLUSTER TASK CONTAINER [--profile PROFILE]"
            exit 1
        fi
        
        cluster=$1
        task=$2
        container=$3
        shift 3
    fi
    
    # プロファイルオプションを解析
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                profile="$2"
                shift 2
                ;;
            *)
                echo "不明なオプション: $1"
                exit 1
                ;;
        esac
    done
    
    # アクションを実行
    case "$action" in
        update)
            update_ecs_lists "$profile"
            ;;
        remove)
            remove_cache "$profile"
            ;;
        connect)
            ecs_execute_command "$cluster" "$task" "$container" "$profile"
            ;;
        *)
            echo "不明なアクション: $action"
            echo "使用法: $0 [update|remove|connect] [--profile PROFILE]"
            echo "        $0 connect CLUSTER TASK CONTAINER [--profile PROFILE]"
            exit 1
            ;;
    esac
}

# スクリプト実行
main "$@"
