#if MOCK_DATA && !MOCK
#error("MOCK_DATA는 MOCK과 함께만 쓸 수 있습니다.")
#endif

#if MOCK && !MOCK_DATA
#error("MOCK은 MOCK_DATA와 함께만 쓸 수 있습니다.")
#endif
