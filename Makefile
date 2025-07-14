# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [UI最终版] 开始编译 ---"
	# 新增 -framework UIKit 以支持UI界面的创建
	clang -v -I. -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES -framework UIKit \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [UI最终版] 编译完成 ---"
