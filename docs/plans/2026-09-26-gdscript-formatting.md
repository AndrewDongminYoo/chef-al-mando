# GDScript 포맷과 린터 도입 계획

## 승인 범위

운영자가 설정 커밋·린터 활성화·reformat PR을 다음 작업으로 지정했습니다.
현재 작업 공간을 사용하고 별도 워크트리를 만들지 않습니다.
머지는 운영자에게 요청하며 upstream 제출과 이슈 생성은 진행하지 않습니다.
Oracle의 해당 프로젝트 검색에서는 일치하는 선례를 찾지 못했습니다.

## 실행 순서

1. `.trunk/trunk.yaml`, `gdlintrc`, `gdformatrc`를 작성하고 실제 도구로 기존 실패를 확인합니다.
2. 파싱 불가 표현 두 곳에 괄호를 추가하고 포맷터의 주석 복제 사례는 원본 보존·포맷터 한정 제외로 처리합니다.
3. `git ls-files`로 확정한 GDScript 경로만 포맷하고 위치별 린터 예외를 검토합니다.
4. 포맷 안정성, 파싱 트리·주석 보존, 의도적인 규칙 위반·파싱 오류의 검출을 확인합니다.
5. 아래 기존 검사를 실행하고 전체 변경을 독립적으로 리뷰합니다.
6. 설정과 GDScript 포맷을 논리적 커밋으로 남긴 뒤 PR을 생성하고 CI·호스팅 리뷰를 확인합니다.
7. 운영자 머지를 요청합니다.

## 검증 명령과 한계

추적 파일 목록을 명시하여 Trunk를 실행합니다.
셸 예시는 Bash에서 실행합니다.

```bash
gd_paths=()
while IFS= read -r gd_path; do
  gd_paths+=("$gd_path")
done < <(git ls-files '*.gd')
trunk fmt --filter=gdformat --no-fix "${gd_paths[@]}"
trunk check --filter=gdlint --no-fix "${gd_paths[@]}"
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
for suite in m0 m1 m2 m3 m4-core m4 m5 mise ui-regressions; do
  bash scripts/check.sh "$suite"
done
python3 tests/test_setup.py
python3 tests/test_m4_restart.py
python3 tests/test_export_check.py
python3 tests/test_ios_export.py
bash scripts/check-export.sh
```

Trunk의 성공은 활성화한 규칙과 검사 경로에 대한 결과입니다.
실행 동작은 기존 Godot 검사로 확인하며 headless 결과가 물리 기기 검증을 대신하지 않습니다.
트리·주석 비교와 실패 검출용 임시 파일은 Git-local 작업 상태에 보관합니다.
