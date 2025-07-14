# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [Metal最终版] 开始编译 ---"
	# 新增 -framework Metal 以支持Metal Hook
	clang -w -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation \
	-framework OpenGLES \
	-framework UIKit \
	-framework CoreGraphics \
	-framework Metal \
	ColorHook1.m -o $(DYLIB_NAME)
	@echo "--- [Metal最终版] 编译完成 ---"
