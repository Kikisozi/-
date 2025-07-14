# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v9 两阶段Hook版] 开始编译 ---"
	clang -w -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation \
	-framework OpenGLES \
	-framework UIKit \
	-framework CoreGraphics \
	-framework Metal \
	ColorHook3.m -o $(DYLIB_NAME)
	@echo "--- [v9 两阶段Hook版] 编译完成 ---"
