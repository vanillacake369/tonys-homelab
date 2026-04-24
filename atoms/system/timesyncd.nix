# Atom: System Time Synchronization (timesyncd)
# 한국(서울) 서버 환경에 최적화된 NTP 풀 설정을 제공합니다.
{...}: {
  services.timesyncd = {
    enable = true;
    # 한국 내 가깝고 안정적인 NTP 서버 목록
    servers = [
      "0.kr.pool.ntp.org"
      "1.kr.pool.ntp.org"
      "2.kr.pool.ntp.org"
      "3.kr.pool.ntp.org"
      "time.google.com"
    ];
  };
}
