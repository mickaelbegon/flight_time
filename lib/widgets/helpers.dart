import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const darkBlue = Color.fromRGBO(0x00, 0x1f, 0x3b, 1);
const lightBlue = Color.fromRGBO(0x05, 0x93, 0xee, 1);
const grayBlue = Color.fromRGBO(0x1b, 0xc7, 0xe3, 1);
const whiteBlue = Color.fromRGBO(0xa6, 0xf6, 0xf9, 1);
const orange = Color.fromRGBO(0xf8, 0xc8, 0x23, 1);
const white = Color.fromRGBO(0xFF, 0xFF, 0xFF, 1);
const black = Color.fromRGBO(0x00, 0x00, 0x00, 1);

Size computeSize(
  BuildContext context, {
  required Size videoSize,
  required double videoAspectRatio,
}) {
  final width = videoSize.width;
  final height = videoSize.height;

  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;

  final widthSizeFactor = width / screenWidth;
  final heightSizeFactor = height / screenHeight;

  final sizeFactor =
      widthSizeFactor > heightSizeFactor ? widthSizeFactor : heightSizeFactor;

  return Size(
    videoSize.width / sizeFactor,
    videoSize.height * videoAspectRatio / sizeFactor,
  );
}

Duration fligthTime({
  required Duration timeJumpStarts,
  required Duration timeJumpEnds,
}) =>
    timeJumpEnds - timeJumpStarts;

double flightHeight({required Duration fligthTime}) {
  final flightTimeSeconds =
      fligthTime.inMicroseconds / Duration.microsecondsPerSecond;
  return 9.81 * flightTimeSeconds * flightTimeSeconds / 8.0;
}

TextStyle get appTitleStyle => GoogleFonts.mateSc();
TextStyle get subtitleStyle => GoogleFonts.mateSc();
TextStyle get mainTextStyle => GoogleFonts.lato();
