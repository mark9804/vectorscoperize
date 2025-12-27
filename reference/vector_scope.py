#!/usr/bin/env python

# NTSC vector scope

import math
import os
import subprocess
import sys
import time
from platform import system

import cv2
import numpy as np

from skimage import io
from skimage.transform import resize

startTime = time.perf_counter()
mode_precise = False

# scope size
cols = 512
rows = 512

# misc constant values
margin = 10
outerlinewidth = 2
outerlinecolor = (128, 128, 128)
small_tick_ratio = 0.98
large_tick_ratio = 0.95
tick_width = 2
dot_radius = 1
vector_len = 8
al_out_angle = 4.
al_out_rad = 0.05
al_thick = 1

# I/Q angle
rad_iq = 33. * math.pi / 180.

# NTSC constants
a_r = 0.701
b_r = -0.587
c_r = -0.114

a_b = -0.299
b_b = -0.587
c_b = 0.886

maxval = 0

def resize_image(original_width, original_height):
    global image
    if original_width <= original_height:
        scale_ratio = float(1024) / float(original_height)
        dimension_resized = (int(original_width * scale_ratio), int(original_height * scale_ratio))
        image = cv2.resize(cv2.imread(argvs[1]), dimension_resized, interpolation=cv2.INTER_AREA)
    elif original_width > original_height:
        scale_ratio = float(1024) / float(original_width)
        dimension_resized = (int(original_width * scale_ratio), int(original_height * scale_ratio))
        image = cv2.resize(cv2.imread(argvs[1]), dimension_resized, interpolation=cv2.INTER_AREA)
    return dimension_resized


def scikit_resize(original_width, original_height):
    global image
    def saveimage(scikit_image):
        global image
        io.imsave('temp.png',scikit_image)
        image=cv2.imread('temp.png')

    if original_width <= original_height:
        scale_ratio = float(1024) / float(original_height)
        dimension_resized = (int(original_width * scale_ratio), int(original_height * scale_ratio))
        image = resize(io.imread(argvs[1]), (int(dimension_resized[1]*scale_ratio), int(dimension_resized[0] * scale_ratio)), anti_aliasing=False)
        saveimage(image)
    elif original_width > original_height:
        scale_ratio = float(1024) / float(original_width)
        dimension_resized = (int(original_width * scale_ratio), int(original_height * scale_ratio))
        image = resize(io.imread(argvs[1]), (int(dimension_resized[1]*scale_ratio), int(dimension_resized[0] * scale_ratio)), anti_aliasing=False)
        saveimage(image)

# a_r = 0.701, b_r = -0.587, c_r = -0.114
def calc_ryby(r, g, b):
    ry = a_r * r + b_r * g + c_r * b
    by = a_b * r + b_b * g + c_b * b
    return ry, by


def calc_ec(ry, by):
    ec = math.sqrt(((ry / 1.14) ** 2) + ((by / 2.03) ** 2))
    return ec


def calc_theta(ry, by):
    theta = math.atan2(ry / 1.14, by / 2.03)
    return theta


def calc_maxval():
    global maxval
    ry = a_r
    by = c_b
    maxval = calc_ec(ry, by)
    return maxval


def calc_transform(r, g, b):
    ry, by = calc_ryby(r, g, b)
    ec = calc_ec(ry, by)
    theta = calc_theta(ry, by)
    return ec, theta


def pole2cart(center_x, center_y, theta, radius):
    x = np.float64(center_x) + np.float64(radius) * math.cos(theta)
    y = np.float64(center_y) - np.float64(radius) * math.sin(theta)
    return int(x), int(y)


def rgb2cart(center_x, center_y, radius, r, g, b, angle_delta):
    global maxval
    ec, theta = calc_transform(r, g, b)
    x, y = pole2cart(center_x, center_y, theta + (angle_delta * math.pi / 180.), ec / maxval * radius)
    return x, y


def draw_allowance(result_img, center_x, center_y, radius, v, c, fontType):
    # inner
    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.0474), v[0], v[1], v[2], 0.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.0474), v[0], v[1], v[2], 0.)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.0474), v[0], v[1], v[2], 2.5)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.0474), v[0], v[1], v[2], 2.5)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.0474), v[0], v[1], v[2], -2.5)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.0474), v[0], v[1], v[2], -2.5)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1.), v[0], v[1], v[2], -2.5)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1.), v[0], v[1], v[2], 2.5)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.0474), v[0], v[1], v[2], -2.5)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. - 0.0474), v[0], v[1], v[2], 2.5)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. + 0.0474), v[0], v[1], v[2], -2.5)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.0474), v[0], v[1], v[2], 2.5)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    # outer
    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], -10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], -10. + al_out_angle)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], -10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. - 0.2 + al_out_rad), v[0], v[1], v[2], -10.)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], 10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], 10. - al_out_angle)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. - 0.2), v[0], v[1], v[2], 10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. - 0.2 + al_out_rad), v[0], v[1], v[2], 10.)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], -10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], -10. + al_out_angle)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], -10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.2 - al_out_rad), v[0], v[1], v[2], -10.)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], 10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], 10. - al_out_angle)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius * (1. + 0.2), v[0], v[1], v[2], 10.)
    x2, y2 = rgb2cart(center_x, center_y, radius * (1. + 0.2 - al_out_rad), v[0], v[1], v[2], 10.)
    cv2.line(result_img, (x, y), (x2, y2), outerlinecolor, al_thick)

    x, y = rgb2cart(center_x, center_y, radius, v[0], v[1], v[2], 0.)
    cv2.putText(result_img, c, (x + vector_len, y - vector_len), fontType, 1, outerlinecolor, 1, 16)


def draw_background(result_img, center_x, center_y, radius):
    # outer circle and tick
    cv2.circle(result_img, (center_x, center_y), radius, outerlinecolor, outerlinewidth, 8)

    radius_div = radius / 5.
    for i in range(1, 5):
        cv2.circle(result_img, (center_x, center_y), int(float(i) * radius_div), outerlinecolor, 1)

    cv2.line(result_img, (center_x - radius, center_y), (center_x + radius, center_y), outerlinecolor, 1)
    cv2.line(result_img, (center_x, center_y - radius), (center_x, center_y + radius), outerlinecolor, 1)

    for i in range(0, 360, 2):
        theta = np.float64(i) / 180 * math.pi
        if (i % 10) == 0:
            r_s = np.float64(radius) * large_tick_ratio
        else:
            r_s = np.float64(radius) * small_tick_ratio

        xs, ys = pole2cart(center_x, center_y, theta, radius)
        xe, ye = pole2cart(center_x, center_y, theta, r_s)
        cv2.line(result_img, (xs, ys),
                 (xe, ye), outerlinecolor, tick_width)

    # I/Q lines
    xs, ys = pole2cart(center_x, center_y, rad_iq, radius)
    xe, ye = pole2cart(center_x, center_y, math.pi + rad_iq, radius)
    cv2.line(result_img, (xs, ys),
             (xe, ye), outerlinecolor, 1)

    xs, ys = pole2cart(center_x, center_y, math.pi * 0.5 + rad_iq, radius)
    xe, ye = pole2cart(center_x, center_y, math.pi * 1.5 + rad_iq, radius)
    cv2.line(result_img, (xs, ys),
             (xe, ye), outerlinecolor, 1)

    # draw vectors
    vec = [[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [0.0, 1.0, 1.0],
           [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [1.0, 1.0, 0.0], [0.25, 0.07, 0.0]]
    col_name = ["B", "G", "CY", "R", "MG", "YL", "SKIN"]

    fontType = cv2.FONT_HERSHEY_PLAIN

    for v, c in zip(vec, col_name):
        draw_allowance(result_img, center_x, center_y, radius, v, c, fontType)


def draw_pixel(result_img, center_x, center_y, radius, bgr):
    global dot_radius
    x, y = rgb2cart(center_x, center_y, radius, bgr[2], bgr[1], bgr[0], 0.)
    col = (int(bgr[0] * 255.), int(bgr[1] * 255.), int(bgr[2] * 255.))
    cv2.circle(result_img, (x, y), dot_radius, col, -1)


if __name__ == '__main__':
    # import a image file
    argvs = sys.argv
    argc = len(argvs)

    if argc < 2:
        print("Usage: vector_scope.py [image]")
        quit()

    for argv_image in sys.argv:
        if argv_image.find('.') != -1:
            img_path = argv_image

    image = cv2.imread(img_path)
    height, width, depth = image.shape
    # accept only rgb
    if depth != 3:
        print("Error. Not RGB image.")
        quit()
    
    print('Original width=', width, ' height=', height, ' depth=', depth)
    # resize big image(dimension >= 1024 * 1024) for better performance

    for argv in sys.argv:
        if argv == '--precise' or argv == '-p':
            print('Resizing disabled by flag "Precise".')
            mode_precise = True

    if max(height, width) >= 1024 and mode_precise is False:
        print('Resizing image for better performance...')
        try:
            width_resized, height_resized = resize_image(width, height)
            print("Resized width=", width_resized, " height=", height_resized)
        except cv2.error:
            try:
                scikit_resize(width, height)
                width_resized, height_resized, depth = image.shape
                print("Resized width=", width_resized, " height=", height_resized)
            except:
                print("Resize failed, using original image for calculation.")
                width_resized, height_resized = width, height
    else:
        width_resized, height_resized = width, height

    # initialize table
    maxval = calc_maxval()

    # create result image in black bg
    center_x = int(cols / 2)
    center_y = int(rows / 2)
    radius = int(rows / 2 - margin)
    result_img = np.zeros((rows, cols, 3), np.uint8)

    # reshape to 1d & hsv conversion
    lin_image = (np.reshape(image, (width_resized * height_resized, 3))).astype(np.float64) / 255.

    # plot all pixels
    for bgr in lin_image:
        draw_pixel(result_img, center_x, center_y, radius, bgr)

    # background
    draw_background(result_img, center_x, center_y, radius)

    # save result to current user GitHub vector_scope directory (macOS only)
    # Will save to current Python working directory on other platforms
    if system() == 'Darwin':
        homedir = os.path.expanduser("~")
        savedir = str(homedir + '/Documents/GitHub/vector_scope/')
        if os.path.exists(savedir):
            cv2.imwrite(savedir + 'result.png', result_img)
            subprocess.call('open ' + savedir + 'result.png', shell=True)
        else:
            savedir = os.getcwd()
            cv2.imwrite('result.png', result_img)
            subprocess.call('open ' + savedir + 'result.png', shell=True)
    else:
        savedir = os.getcwd()
        cv2.imwrite('result.png', result_img)
        print('Result saved as ' + savedir + 'result.png')

    # show vectorscope
    # cv2.imshow('vectorscope', result_img)

    # If temporary file is generated using alternative resizing method, then delete temp file
    if os.path.exists('temp.png'):
        print('Cleaning temporary file...')
        os.remove('temp.png')
    else:
        pass


    endTime = time.perf_counter()
    print('Runtime: ' + str(endTime - startTime) + 's')
