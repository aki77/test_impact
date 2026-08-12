---
name: impacted-specs
description: ローカルで変更したコード（未コミットの変更を含む）に対して、実行すべき RSpec テスト（spec）を検出したいときに使う。test_impact gem の GitHub Actions collect ワークフローが生成した coverage map を最新化してから `test-impact plan` を実行し、影響を受ける spec だけを絞り込む。「変更に関連するテストだけ実行したい」「影響範囲のspecを調べて」「今の変更でどのテストを回すべきか」「diffに対応するspecを教えて」といった依頼で使う。
license: MIT
---

# impacted-specs

このスキルは **test_impact gem の利用先プロジェクト**で実行される。ローカル（未コミットの変更を
含む）の変更から、実行すべき spec を検出する。

前提:
- `gh` CLI が認証済みであること
- 利用先プロジェクトの `Gemfile` に `test_impact` gem が入っていること
- そのプロジェクトの GitHub Actions で collect ワークフローが稼働しており、artifact 名
  `test-impact-map` で coverage map をアップロードしていること

## 手順

### 1. base の最新化

`.test_impact.yml` の `base`（既定 `origin/main`）を確認し、対応するリモートブランチを fetch する:

```sh
git fetch origin main
```

理由: ローカルの `origin/main` が古いと、map の `commit_sha` が履歴到達性チェックに失敗して
全実行（`all`）に落ちる。

### 2. map の取得（毎回・自動探索）

ローカルに map があっても鮮度判定はせず、**常に最新の artifact をダウンロードして上書きする**。
特定のワークフロー名には依存しない:

```sh
run_id=$(gh api 'repos/{owner}/{repo}/actions/artifacts?name=test-impact-map&per_page=1' \
  --jq '.artifacts[] | select(.expired == false) | .workflow_run.id' | head -1)
rm -f .test_impact/map.json.gz
gh run download "$run_id" -n test-impact-map -D .test_impact
```

注記:
- `expired` の判定は `== false` の明示比較を使う（`//` は `false` も falsy として右辺に
  フォールバックしてしまうため、`enabled // true` 的な書き方は誤判定する）。
- `gh run download` は出力先に同名ファイルが既にあると失敗するため、先に `rm -f` で削除する。
- `run_id` が取れない（artifact が見つからない）場合は、collect ワークフローが未整備である旨を
  ユーザーに報告してここで終了する。

### 3. plan 実行

```sh
bundle exec test-impact plan --format json --include-uncommitted > /tmp/plan.json
```

`--format json` は常に exit 0。stdout は 1 行の JSON
`{"mode":"all|partial|none","spec_files":[...],"reason":null|"..."}`。
診断情報（mode / reason / spec_files 件数など）は stderr に出る。

### 4. 結果の解釈

- `mode: "partial"` → 対象の spec だけ実行する:
  ```sh
  bundle exec rspec $(jq -r '.spec_files[]' /tmp/plan.json)
  ```
- `mode: "none"` → 実行すべき spec はないとユーザーに報告する。
- `mode: "all"` → **全 suite を勝手に実行しない。** 全実行が必要な旨と `reason` をユーザーに
  報告し、判断を仰ぐ。`reason` の主な例:
  - `uncovered file changed: <path>` — 新規または未収集のファイルが変更された
  - `no map available or backend invalid` — map が取得できない、または不備がある

## 注意点

- `.test_impact/` を利用先プロジェクトの `.gitignore` に入れていないと、map 自身が
  untracked の新規ファイルとして扱われ、全実行を誘発する。
- shallow clone では merge-base の計算に失敗し、全実行になる。
- `--include-uncommitted` は staged / unstaged / untracked の変更を diff 対象に含めるが、
  リポジトリの状態は一切変更しない（read-only）。
