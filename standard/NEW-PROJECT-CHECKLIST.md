# 새 프로젝트 준비 체크리스트 (STANDARD.md v1.1)

기존 PoC에 적용할 때도 같은 순서를 따른다.

1. [ ] **폴더 파악**: 코드·결과물·비밀 파일·누적 데이터 폴더를 구분한다 (특히 `runs/` 같은 이름이 파이프라인 규칙과 겹치는지)
2. [ ] **PROJECT.md**: `PROJECT.template.md`로 만들거나, 기존 문서 맨 위에 "기준: STANDARD.md v1.1"과 "기준 예외" 절을 넣는다
3. [ ] **.gitignore**: `gitignore.template` 내용 + 이 프로젝트의 대용량 결과물·비밀 파일
4. [ ] **Git**: `git init -b main` → 제외 목록 확인(`git status`) → 첫 커밋. 작성자 이름·이메일 설정 확인
5. [ ] **원격 저장소**: 공개 여부를 PROJECT.md에 적고 GitHub에 만든다 (빈 저장소로: README 자동 생성 끄기)
6. [ ] **pipeline.json**: `pipeline.template.json`으로 만들고 ②가 쓸 폴더, 시간 제한, 옮길 출력 폴더를 정한다
7. [ ] **TASK.md**: `TASK.template.md`로 첫 작업을 쓴다 (작게, 외부 접속 없이 확인할 수 있는 것부터)
8. [ ] **가짜 실행**: n8n mode=`fake`로 흐름 확인
9. [ ] **실제 실행**: 필요한 단계만 real로 → 전체 real 1회 → ⑦ 판정
