class_name JourneyData
extends Resource
## A Journey [JourneyData] is a collection of Stages [StageData].
## I created this so I could quickly plug into [StageDirector] and have a
## different sets of stages for testing purposes.

@export var id: StringName = &""
@export var name: String = ""
@export var stages: Array[StageData] = []
