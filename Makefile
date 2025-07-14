# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v8 最终链接修正版] 开始编译 ---"
	# 【最终修正】新增链接 CoreGraphics 框架，解决 CGPointZero 未定义的错误
	clang -w -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation \
	-framework OpenGLES \
	-framework UIKit \
	-framework CoreGraphics \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [v8 最终链接修正版] 编译完成 ---"
