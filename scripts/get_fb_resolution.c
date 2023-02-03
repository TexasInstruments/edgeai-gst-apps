#include <stdio.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define	FB_DEV	"/dev/fb0"

int main(int argc, char *argv[])
{
	int				fbdev;
	struct fb_var_screeninfo	fb_vinfo;

	fbdev = open(FB_DEV, O_RDWR);
	ioctl(fbdev, FBIOGET_VSCREENINFO, &fb_vinfo);

	printf("video/x-raw, width=%d, height=%d", fb_vinfo.xres, fb_vinfo.yres);

	close(fbdev);

	return 0;
}
