# TASK.md — v1 더미 작업 (2026-11-22)

> 상태: 확정 (2026-11-22, 사용자 결정). v1 실제 실행의 작업으로 쓴다.

## 할 일
- `work/hello.py`를 만든다. 실행하면 `runs/output.txt`에 `pipeline ok` 한 줄을 쓴다.

## 실행 명령 (④ 단계에서 stage.ps1이 그대로 실행, 한 줄)
RUN: python work/hello.py

## 완료 조건
1. `python work/hello.py` 종료 코드 0
2. `runs/output.txt` 내용이 정확히 `pipeline ok`
3. REPORT.md 맨 위에 무엇을 만들었고 어떻게 확인했는지 적는다
